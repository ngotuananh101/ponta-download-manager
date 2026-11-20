import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_core/src/chunk_sink.dart';
import 'package:download_core/src/segment.dart';
import 'package:download_core/src/segment_planner.dart';
import 'package:download_core/src/segment_progress.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_transport/download_transport.dart';
import 'package:logging/logging.dart';

final _log = Logger('DownloadTask');

/// Thrown when a server answers a range request with more bytes than the
/// requested range: the server ignored Range (§5.3).
class _RangeIgnored implements Exception {
  const _RangeIgnored();
}

/// Mutable download progress of one segment.
class _SegmentState {
  _SegmentState(this.segment);

  final Segment segment;
  var downloaded = 0;

  bool get isComplete =>
      segment.length != null && downloaded >= segment.length!;
}

/// Runs one download: probe, validate, plan, fetch segments, report
/// progress (docs/architecture.md §5.1, §6, §7).
class DownloadTask {
  DownloadTask({
    required this.transport,
    required this.sink,
    required this.url,
    required this.id,
    this.maxConnections = 4,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.resumeFrom = const [],
    this.limiter,
    this.priority = 0,
    this.cookie,
    this.referrer,
  }) : _headers = _buildHeaders(cookie, referrer);

  /// Builds the request headers once from the browser-supplied values.
  /// The HTTP header is spelled `referer`; the Dart field stays
  /// `referrer`.
  static Map<String, String>? _buildHeaders(
    String? cookie,
    String? referrer,
  ) {
    if (cookie == null && referrer == null) {
      return null;
    }
    return {
      'cookie': ?cookie,
      'referer': ?referrer,
    };
  }

  final DownloadTransport transport;
  final ChunkSink sink;
  final Uri url;
  final String id;
  final int maxConnections;
  final int maxRetries;
  final Duration retryDelay;
  final List<SegmentProgress> resumeFrom;
  final BandwidthLimiter? limiter;
  final int priority;

  /// Browser session cookie for this download, when the extension
  /// supplied one. In-memory only: never persisted, never logged.
  final String? cookie;

  /// Page the download came from, when the extension supplied one.
  /// In-memory only: never persisted, never logged.
  final String? referrer;

  final Map<String, String>? _headers;

  DownloadStatus get status => _status;
  int get downloadedBytes => _downloaded;

  /// Total bytes when known, -1 when unknown.
  int get totalBytes => _total;

  /// ETag validator from the probe, when the server sent one.
  String? get eTag => _eTag;

  /// URL after following redirects, when the probe ran.
  Uri? get finalUrl => _finalUrl;

  /// Live per-segment progress. Empty before the segments are planned.
  List<SegmentProgress> get segments => _segmentStates
      .map(
        (s) => SegmentProgress(
          segmentId: s.segment.id,
          start: s.segment.start,
          end: s.segment.end,
          downloaded: s.downloaded,
        ),
      )
      .toList();

  Stream<DownloadEvent> get events => _events.stream;

  DownloadStatus _status = DownloadStatus.queued;
  int _downloaded = 0;
  int _total = -1;
  String? _fileName;
  String? _eTag;
  Uri? _finalUrl;
  final _segmentStates = <_SegmentState>[];
  final _events = StreamController<DownloadEvent>.broadcast();
  // Speed sampling window: the rate is recomputed from the bytes
  // downloaded in the last window, so a single fast chunk does not
  // spike the reading and the value tracks the current rate.
  static const _speedWindow = Duration(milliseconds: 500);
  DateTime? _speedWindowStart;
  int _speedWindowBytes = 0;
  int _bytesPerSecond = 0;
  bool _paused = false;
  bool _cancelled = false;
  bool _aborted = false;
  Completer<void>? _resumeGate;
  // Completed by pause(), cancel() and _abort() so a segment
  // waiting on the token bucket wakes up instead of sitting in
  // the queue until tokens arrive. Reset by resume().
  Completer<void>? _cancelGate;
  final _iterators = <StreamIterator<List<int>>, Future<void>?>{};
  // Segment boundaries are fixed for checkpoints. Only request admission
  // changes, and successful streams are allowed to finish at the old limit.
  var _connectionLimit = 1;
  var _activeRequests = 0;
  Completer<void>? _requestChanged;
  final _requestClock = Stopwatch()..start();
  var _cooldownUntil = Duration.zero;
  var _sinkClosed = false;

  /// Starts the download. Subscribe to [events] before calling this.
  /// Returns the final [DownloadInfo] for completed and cancelled runs;
  /// throws [DownloadError] when the download fails.
  Future<DownloadInfo> run() async {
    _setStatus(DownloadStatus.queued);
    try {
      final info = await transport.probe(url, headers: _headers);
      _total = info.contentLength ?? -1;
      _fileName = info.fileName;
      _eTag = info.eTag;
      _finalUrl = info.finalUrl;
      var segmented = false;
      if (info.supportsRange &&
          info.contentLength != null &&
          info.contentLength! > 0) {
        final validation = await transport.validateRange(
          url,
          start: 0,
          end: 0,
          headers: _headers,
        );
        segmented = validation.valid;
        if (segmented &&
            validation.totalBytes != null &&
            validation.totalBytes != _total) {
          // HEAD and Content-Range disagree: trust the range response,
          // which describes the representation that will actually be
          // downloaded, before planning segments over the total.
          _log.info(
            'HEAD said $_total bytes but Content-Range says '
            '${validation.totalBytes}; using the range total',
          );
          _total = validation.totalBytes!;
        }
      }
      // A pause that landed during the probe takes effect here: wait
      // for resume instead of starting the download while paused.
      await _waitIfPaused();
      if (_cancelled) {
        return _finish(DownloadStatus.cancelled);
      }
      _setStatus(DownloadStatus.downloading);
      try {
        if (segmented) {
          final segments = planSegments(
            totalBytes: _total,
            maxConnections: maxConnections,
          );
          _segmentStates.clear();
          _segmentStates.addAll(segments.map(_stateFor));
          _downloaded = _segmentStates.fold(
            0,
            (sum, s) => sum + s.downloaded,
          );
          _connectionLimit = _segmentStates.length;
          await Future.wait(_segmentStates.map(_runSegment));
        } else {
          const single = Segment(id: 0, start: 0, end: null);
          _segmentStates.clear();
          _segmentStates.add(_stateFor(single));
          _downloaded = _segmentStates.first.downloaded;
          await _runSegment(_segmentStates.first);
        }
      } on _RangeIgnored {
        await _fallbackToSingleStream();
      }
      if (_cancelled) {
        return _finish(DownloadStatus.cancelled);
      }
      if (_total >= 0 && _downloaded != _total) {
        throw DownloadError(
          'size-mismatch',
          'Downloaded $_downloaded bytes, expected $_total',
        );
      }
      return _finish(DownloadStatus.completed);
    } on DownloadError catch (e) {
      _fail(e);
      rethrow;
    } catch (e) {
      final wrapped = DownloadError('internal', e.toString());
      _fail(wrapped);
      throw wrapped;
    } finally {
      DownloadError? closeFailure;
      try {
        await _closeSink();
      } catch (e) {
        // The download already reported completed, but its sink never
        // closed: the file is not final. Report the failure instead of
        // leaving a completed status on a .partial file. The scheduler
        // holds the completed event back, so the failed event is the
        // one the UI sees.
        if (_status == DownloadStatus.completed) {
          closeFailure = DownloadError(
            'close-failed',
            'Could not close the file: $e',
          );
          _fail(closeFailure);
        }
        // Otherwise the download already failed or was cancelled; the
        // close failure adds nothing and the original outcome stands.
      }
      // Always close the event stream before run() returns or throws,
      // so every event added above has been delivered by then.
      await _events.close();
      if (closeFailure != null) {
        throw closeFailure;
      }
    }
  }

  void pause() {
    // Also accepts queued: the task may still be probing, and a pause
    // then must stick — run() waits on the resume gate after the probe
    // instead of switching to downloading.
    if (_status == DownloadStatus.completed ||
        _status == DownloadStatus.failed ||
        _status == DownloadStatus.cancelled) {
      return;
    }
    _paused = true;
    _setStatus(DownloadStatus.paused);
    _completeCancelGate();
    _cancelIterators();
    _notifyRequestChanged();
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    _setStatus(DownloadStatus.downloading);
    _cancelGate = null;
    final gate = _resumeGate;
    _resumeGate = null;
    gate?.complete();
    _notifyRequestChanged();
  }

  void cancel() {
    if (_status == DownloadStatus.completed ||
        _status == DownloadStatus.failed ||
        _status == DownloadStatus.cancelled) {
      return;
    }
    _cancelled = true;
    _paused = false;
    _completeCancelGate();
    final gate = _resumeGate;
    _resumeGate = null;
    gate?.complete();
    _cancelIterators();
    _notifyRequestChanged();
  }

  DownloadInfo _finish(DownloadStatus status) {
    _setStatus(status);
    final info = DownloadInfo(
      id: id,
      url: url.toString(),
      fileName: _fileName ?? 'download',
      status: status,
      downloadedBytes: _downloaded,
      totalBytes: _total,
    );
    if (status == DownloadStatus.completed) {
      _events.add(
        DownloadEvent.completed(downloadId: id, filePath: sink.filePath ?? ''),
      );
    }
    return info;
  }

  void _fail(DownloadError error) {
    _setStatus(DownloadStatus.failed);
    _events.add(
      DownloadEvent.failed(
        downloadId: id,
        code: error.code,
        message: error.message,
      ),
    );
  }

  void _setStatus(DownloadStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    _events.add(DownloadEvent.stateChanged(downloadId: id, status: status));
  }

  void _emitProgress() {
    final now = DateTime.now();
    final start = _speedWindowStart;
    if (start == null) {
      // First chunk: start the window. The speed stays 0 until the
      // window elapses, so a sub-second download never reports a
      // meaningless one-chunk rate.
      _speedWindowStart = now;
      _speedWindowBytes = _downloaded;
    } else {
      final elapsed = now.difference(start);
      if (elapsed >= _speedWindow) {
        final bytes = _downloaded - _speedWindowBytes;
        final micros = elapsed.inMicroseconds;
        _bytesPerSecond = micros > 0
            ? (bytes * 1000000 / micros).round()
            : 0;
        _speedWindowStart = now;
        _speedWindowBytes = _downloaded;
      }
    }
    _events.add(
      DownloadEvent.progress(
        downloadId: id,
        downloadedBytes: _downloaded,
        totalBytes: _total,
        bytesPerSecond: _bytesPerSecond,
      ),
    );
  }

  _SegmentState _stateFor(Segment segment) {
    final state = _SegmentState(segment);
    for (final entry in resumeFrom) {
      if (entry.segmentId == segment.id &&
          entry.start == segment.start &&
          entry.end == segment.end) {
        final length = segment.length;
        state.downloaded = length == null
            ? entry.downloaded
            : entry.downloaded.clamp(0, length);
        break;
      }
    }
    return state;
  }

  Future<void> _fallbackToSingleStream() async {
    if (_cancelled) {
      return;
    }
    _log.info(
      'Server ignored Range for $url; falling back to single-stream',
    );
    _abort();
    _aborted = false;
    if (!_paused) {
      _cancelGate = null;
    }
    _connectionLimit = 1;
    _downloaded = 0;
    const single = Segment(id: 0, start: 0, end: null);
    _segmentStates.clear();
    _segmentStates.add(_SegmentState(single));
    await _runSegment(_segmentStates.first);
  }

  Future<void> _runSegment(_SegmentState state) async {
    final segment = state.segment;
    var attempts = 0;
    var retryAt = Duration.zero;
    while (!state.isComplete) {
      final admittedLimit = await _admitRequest(retryAt);
      if (admittedLimit == null) {
        return;
      }
      _cancelGate ??= Completer<void>();
      final interrupted = _cancelGate!;
      try {
        if (_cancelled || _aborted) {
          return;
        }
        if (_paused) {
          continue;
        }
        await _pumpSegment(segment, state, interrupted, () => attempts = 0);
        if (interrupted.isCompleted) {
          continue;
        }
        if (state.isComplete || segment.length == null) {
          return;
        }
        throw DownloadError(
          'truncated',
          'Stream ended before segment ${segment.id} was complete',
        );
      } on _RangeIgnored {
        if (_aborted) {
          return;
        }
        _abort();
        rethrow;
      } on DownloadError catch (error) {
        if (interrupted.isCompleted) {
          continue;
        }
        if (error.code == 'range-ignored') {
          _abort();
          throw const _RangeIgnored();
        }
        if (_cancelled || _aborted) {
          return;
        }
        final overloaded = error.code == 'http-429' || error.code == 'http-503';
        final shouldBackOffConnections = maxRetries > 0 && admittedLimit > 1 &&
            (overloaded || (attempts > 0 &&
                (error.code == 'network' || error.code == 'timeout')));
        if (!_isTransient(error) ||
            (!shouldBackOffConnections && attempts >= maxRetries)) {
          _abort();
          rethrow;
        }
        final backoff = _backoffDelay(attempts + 1);
        if (shouldBackOffConnections) {
          // A rejected request gets a chance at the lower limit without
          // spending a retry. Late errors from the same burst share that
          // reduction; every subsequent burst can only step down to one.
          if (admittedLimit == _connectionLimit) {
            _connectionLimit ~/= 2;
            _log.fine('Reducing download request limit to $_connectionLimit');
          }
        } else {
          attempts++;
        }
        final now = _requestClock.elapsed;
        retryAt = now + backoff;
        if (overloaded) {
          final serverDelay = error.retryAfter;
          final until = serverDelay != null && serverDelay > backoff
              ? now + serverDelay
              : retryAt;
          if (until > _cooldownUntil) {
            _cooldownUntil = until;
          }
        }
        _log.fine('Segment ${segment.id} failed (${error.code}); '
            'retry budget used: $attempts/$maxRetries');
      } catch (_) {
        if (_cancelled || _aborted) {
          return;
        }
        _abort();
        rethrow;
      } finally {
        _activeRequests--;
        _notifyRequestChanged();
      }
    }
  }

  Future<int?> _admitRequest(Duration retryAt) async {
    while (!_cancelled && !_aborted) {
      await _waitIfPaused();
      if (_cancelled || _aborted || _paused) {
        continue;
      }
      final available = _activeRequests < _connectionLimit;
      final readyAt = retryAt > _cooldownUntil ? retryAt : _cooldownUntil;
      final remaining = readyAt - _requestClock.elapsed;
      if (available && remaining <= Duration.zero) {
        _activeRequests++;
        return _connectionLimit;
      }
      _requestChanged ??= Completer<void>();
      final changed = _requestChanged!.future;
      if (!available) {
        await changed;
      } else {
        final elapsed = Completer<void>();
        final timer = Timer(remaining, elapsed.complete);
        try {
          await Future.any([changed, elapsed.future]);
        } finally {
          timer.cancel();
        }
      }
    }
    return null;
  }

  void _notifyRequestChanged() {
    final changed = _requestChanged;
    _requestChanged = null;
    changed?.complete();
  }

  Future<void> _pumpSegment(
    Segment segment,
    _SegmentState state,
    Completer<void> interrupted,
    void Function() onProgress,
  ) async {
    final start = segment.start + state.downloaded;
    final stream = transport.openStream(
      url,
      start: start,
      end: segment.end,
      ifRange: _eTag,
      headers: _headers,
    );
    final iterator = StreamIterator<List<int>>(stream);
    _iterators[iterator] = null;
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        final remaining = segment.length == null
            ? null
            : segment.length! - state.downloaded;
        if (remaining != null && chunk.length > remaining) {
          throw const _RangeIgnored();
        }
        if (chunk.isEmpty) {
          continue;
        }
        if (interrupted.isCompleted) {
          return;
        }
        final throttle = limiter;
        if (throttle != null) {
          await _acquireOrCancel(throttle, chunk.length);
        }
        if (interrupted.isCompleted) {
          return;
        }
        await sink.write(segment.start + state.downloaded, chunk);
        state.downloaded += chunk.length;
        _downloaded += chunk.length;
        onProgress();
        _emitProgress();
        if (interrupted.isCompleted) {
          return;
        }
      }
    } finally {
      final cancellation = _iterators.remove(iterator);
      await (cancellation ?? iterator.cancel());
    }
  }

  Future<void> _waitIfPaused() async {
    if (!_paused) {
      return;
    }
    _resumeGate ??= Completer<void>();
    await _resumeGate!.future;
  }

  /// Waits for bandwidth tokens, or returns early when the download
  /// is paused, cancelled or aborted: a bare `await acquire(...)`
  /// would sit in the bucket queue until tokens arrive, so neither
  /// pause nor cancel could interrupt it.
  Future<void> _acquireOrCancel(BandwidthLimiter limiter, int bytes) async {
    _cancelGate ??= Completer<void>();
    if (_cancelled || _aborted || _paused) {
      return;
    }
    final acquired = limiter.acquire(id, bytes, priority: priority);
    // The acquire stays queued in the bucket after the gate wins the
    // race; swallow its eventual outcome so it can never surface as
    // an unhandled error (e.g. when the bucket is disposed).
    unawaited(acquired.then((_) {}, onError: (_) {}));
    await Future.any([acquired, _cancelGate!.future]);
  }

  void _completeCancelGate() {
    final gate = _cancelGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void _abort() {
    _aborted = true;
    _completeCancelGate();
    _cancelIterators();
    _notifyRequestChanged();
  }

  void _cancelIterators() {
    for (final iterator in _iterators.keys.toList()) {
      // Keep the first cancellation future: a second cancel() does not
      // wait for cleanup. Late errors from an interrupted stream belong
      // to that request and must not escape as unhandled async errors.
      _iterators[iterator] ??= iterator.cancel().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _log.fine('Interrupted stream closed with an error', error, stack);
        },
      );
    }
  }

  Future<void> _closeSink() async {
    if (_sinkClosed) {
      return;
    }
    _sinkClosed = true;
    await sink.close();
  }

  Duration _backoffDelay(int attempt) {
    return retryDelay * (1 << (attempt - 1));
  }

  bool _isTransient(DownloadError error) {
    switch (error.code) {
      case 'network':
      case 'timeout':
      case 'truncated':
      case 'http-429':
        return true;
      default:
        if (error.code.startsWith('http-')) {
          final status = int.tryParse(error.code.substring(5));
          return status != null && status >= 500 && status < 600;
        }
        return false;
    }
  }
}
