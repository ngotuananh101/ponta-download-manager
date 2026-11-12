import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_storage/download_storage.dart';
import 'package:download_transport/download_transport.dart';
import 'package:logging/logging.dart';

import 'download_job.dart';

export 'download_job.dart';

final _log = Logger('DownloadScheduler');

/// A started task plus the sink it writes to. The scheduler finishes the
/// sink (renames the partial file) when the task completes.
class ScheduledTask {
  const ScheduledTask(this.task, this.sink);

  final DownloadTask task;
  final ChunkSink sink;
}

/// Builds the task (and its sink) for a job. The scheduler owns the
/// returned task until it reaches a terminal state.
typedef DownloadTaskFactory = Future<ScheduledTask> Function(DownloadJob job);

class _QueuedJob {
  _QueuedJob(
    this.job, {
    this.started,
    this.subscription,
    this.runStarted = false,
  });

  final DownloadJob job;
  final ScheduledTask? started;
  final StreamSubscription<DownloadEvent>? subscription;
  final bool runStarted;
  bool paused = false;
}

class _RunningJob {
  _RunningJob(
    this.job,
    this.started,
    this.subscription, {
    required this.runStarted,
  });

  final DownloadJob job;
  final ScheduledTask started;
  final StreamSubscription<DownloadEvent> subscription;

  /// False when the task was paused before its run() was ever called.
  final bool runStarted;
}

/// Runs downloads with a priority queue and a limit on concurrent
/// downloads (docs/architecture.md §8.3, §21.5). In-memory only:
/// persistence lives in download_recovery. Bandwidth limiting is
/// enforced when the scheduler is constructed with a limiter.
class DownloadScheduler {
  DownloadScheduler({
    int maxConcurrent = 3,
    int maxTotalConnections = 16,
    DownloadTaskFactory? taskFactory,
    DownloadTransport? transport,
    this.limiter,
  }) : _maxConcurrent = maxConcurrent,
       _maxTotalConnections = maxTotalConnections,
       _ownsTransport = transport == null && taskFactory == null {
    _transport = transport;
    _taskFactory = taskFactory ?? _defaultTaskFactory;
  }

  /// Optional limiter, owned by the caller. A custom taskFactory
  /// wires its own limiter; the default factory uses this one.
  final BandwidthLimiter? limiter;

  int get maxConcurrent => _maxConcurrent;

  int _maxConcurrent;

  /// Maximum total connections (open segment streams) across all
  /// running downloads (docs/architecture.md §5.6). A running job
  /// reserves its whole `maxConnections` up front: a task opens at
  /// most that many streams at once, so the sum over running jobs is
  /// the upper bound on open connections. Default 16, configurable
  /// later via Settings.
  int get maxTotalConnections => _maxTotalConnections;

  int _maxTotalConnections;

  /// Changes the cap at runtime; jobs waiting on budget start when
  /// it grows.
  void setMaxTotalConnections(int value) {
    _maxTotalConnections = value;
    _pump();
  }
  DownloadTransport? _transport;
  late final DownloadTaskFactory _taskFactory;
  final bool _ownsTransport;

  final _pending = <_QueuedJob>[];
  final _running = <String, _RunningJob>{};
  final _pausedRunning = <String, _RunningJob>{};
  final _starting = <String>{};
  final _cancelledWhileStarting = <String>{};
  final _pausedWhileStarting = <String>{};
  final _jobs = <String, DownloadJob>{};
  final _infos = <String, DownloadInfo>{};
  final _events = StreamController<DownloadEvent>.broadcast();
  var _counter = 0;
  var _sequence = 0;
  var _disposed = false;

  /// All task events plus scheduler lifecycle events, in order.
  Stream<DownloadEvent> get events => _events.stream;

  /// Latest known info for every download, in enqueue order.
  List<DownloadInfo> get downloads => List.of(_infos.values);

  /// Live per-segment progress for a download the scheduler currently
  /// holds (running or paused). Null when the download is not held
  /// (queued but not started, or finished), so the caller falls back
  /// to the checkpointed segments in the store.
  List<SegmentProgress>? liveSegments(String downloadId) {
    final running = _running[downloadId];
    if (running != null) {
      return running.started.task.segments;
    }
    final paused = _pausedRunning[downloadId];
    if (paused != null) {
      return paused.started.task.segments;
    }
    return null;
  }

  /// Advances the id counter past [id] (e.g. 'dl-7'), so a later
  /// generated id never collides with an id that already exists.
  /// Recovery only re-enqueues non-terminal downloads, so on engine
  /// open the counter must also be seeded from the terminal records
  /// in the store, or the next generated id would overwrite one.
  void reserveId(String id) {
    final match = RegExp(r'^dl-(\d+)$').firstMatch(id);
    if (match != null) {
      final n = int.parse(match.group(1)!);
      if (n >= _counter) {
        _counter = n + 1;
      }
    }
  }

  /// Enqueues a download and returns its id. Starts it right away when
  /// a slot is free.
  String enqueue({
    required String url,
    required String fileName,
    String directory = '.',
    int priority = 0,
    int maxConnections = 4,
    String? id,
    List<SegmentProgress> resumeFrom = const [],
    bool resumeExisting = false,
    bool overwrite = false,
    // Starts the job paused: it sits in the pending queue and _pump()
    // skips it until resume(id) un-pauses it. Used by startup recovery
    // for downloads the user had paused.
    bool paused = false,
  }) {
    _throwIfDisposed();
    final jobId = id ?? 'dl-${++_counter}';
    if (id != null) {
      final match = RegExp(r'^dl-(\d+)$').firstMatch(id);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n >= _counter) {
          _counter = n + 1;
        }
      }
    }
    final job = DownloadJob(
      id: jobId,
      url: url,
      fileName: fileName,
      directory: directory,
      priority: priority,
      maxConnections: maxConnections,
      sequence: ++_sequence,
      resumeFrom: resumeFrom,
      resumeExisting: resumeExisting,
      overwrite: overwrite,
    );
    _jobs[job.id] = job;
    _infos[job.id] = DownloadInfo(
      id: job.id,
      url: url,
      fileName: fileName,
      status: paused ? DownloadStatus.paused : DownloadStatus.queued,
      totalBytes: -1,
    );
    final queued = _QueuedJob(job)..paused = paused;
    _pending.add(queued);
    _emit(
      DownloadEvent.stateChanged(
        downloadId: job.id,
        status: paused ? DownloadStatus.paused : DownloadStatus.queued,
      ),
    );
    _pump();
    return job.id;
  }

  /// Pauses a running download (freeing its slot) or a queued one.
  void pause(String id) {
    _throwIfDisposed();
    final running = _running.remove(id);
    if (running != null) {
      running.started.task.pause();
      _pausedRunning[id] = running;
      _pump();
      return;
    }
    if (_pausedRunning.containsKey(id)) {
      return;
    }
    if (_starting.contains(id)) {
      _pausedWhileStarting.add(id);
      return;
    }
    final queued = _findPending(id);
    if (queued != null && !queued.paused) {
      queued.paused = true;
      final info = _infos[id];
      if (info != null) {
        _infos[id] = info.copyWith(status: DownloadStatus.paused);
      }
      _emit(
        DownloadEvent.stateChanged(
          downloadId: id,
          status: DownloadStatus.paused,
        ),
      );
    }
  }

  /// Changes the priority of a queued or paused download. A running
  /// download keeps the priority it started with.
  void setPriority(String id, int priority) {
    _throwIfDisposed();
    final queuedIndex = _pending.indexWhere((q) => q.job.id == id);
    if (queuedIndex != -1) {
      final queued = _pending[queuedIndex];
      _pending[queuedIndex] = _QueuedJob(
        _withPriority(queued.job, priority),
        started: queued.started,
        subscription: queued.subscription,
        runStarted: queued.runStarted,
      )..paused = queued.paused;
      _jobs[id] = _pending[queuedIndex].job;
      _pump();
      return;
    }
    final paused = _pausedRunning[id];
    if (paused != null) {
      _pausedRunning[id] = _RunningJob(
        _withPriority(paused.job, priority),
        paused.started,
        paused.subscription,
        runStarted: paused.runStarted,
      );
      _jobs[id] = _pausedRunning[id]!.job;
    }
  }

  DownloadJob _withPriority(DownloadJob job, int priority) {
    return DownloadJob(
      id: job.id,
      url: job.url,
      fileName: job.fileName,
      directory: job.directory,
      priority: priority,
      maxConnections: job.maxConnections,
      sequence: job.sequence,
      resumeFrom: job.resumeFrom,
      resumeExisting: job.resumeExisting,
      overwrite: job.overwrite,
    );
  }

  /// Resumes a paused download. It re-enters the queue and starts when
  /// a slot is free.
  void resume(String id) {
    _throwIfDisposed();
    final paused = _pausedRunning.remove(id);
    if (paused != null) {
      _pending.add(
        _QueuedJob(
          paused.job,
          started: paused.started,
          subscription: paused.subscription,
          runStarted: paused.runStarted,
        ),
      );
      _pump();
      return;
    }
    final queued = _findPending(id);
    if (queued != null && queued.paused) {
      queued.paused = false;
      final info = _infos[id];
      if (info != null) {
        _infos[id] = info.copyWith(status: DownloadStatus.queued);
      }
      _emit(
        DownloadEvent.stateChanged(
          downloadId: id,
          status: DownloadStatus.queued,
        ),
      );
      _pump();
    }
  }

  /// Cancels a download in any state. A running task is cancelled
  /// through the task itself; its completion handler settles the rest.
  void cancel(String id) {
    _throwIfDisposed();
    final running = _running[id] ?? _pausedRunning[id];
    if (running != null) {
      if (running.runStarted) {
        running.started.task.cancel();
      } else {
        _pausedRunning.remove(id);
        unawaited(running.subscription.cancel());
        unawaited(running.started.sink.close());
        _markCancelled(running.job);
        _pump();
      }
      return;
    }
    if (_starting.contains(id)) {
      _cancelledWhileStarting.add(id);
      final job = _jobs[id];
      if (job != null) {
        _markCancelled(job);
      }
      return;
    }
    final queued = _findPending(id);
    if (queued != null) {
      _pending.remove(queued);
      if (queued.started != null) {
        unawaited(queued.subscription!.cancel());
        queued.started!.task.cancel();
      }
      _markCancelled(queued.job);
    }
  }

  /// Pauses every running and queued download.
  void pauseAll() {
    _throwIfDisposed();
    for (final queued in _pending) {
      if (!queued.paused) {
        queued.paused = true;
        final info = _infos[queued.job.id];
        if (info != null) {
          _infos[queued.job.id] = info.copyWith(
            status: DownloadStatus.paused,
          );
        }
        _emit(
          DownloadEvent.stateChanged(
            downloadId: queued.job.id,
            status: DownloadStatus.paused,
          ),
        );
      }
    }
    for (final id in _running.keys.toList()) {
      pause(id);
    }
  }

  /// Resumes every paused download.
  void resumeAll() {
    _throwIfDisposed();
    for (final id in _pausedRunning.keys.toList()) {
      resume(id);
    }
    for (final queued in _pending.where((q) => q.paused).toList()) {
      resume(queued.job.id);
    }
  }

  /// Changes the global bandwidth limit at runtime. No-op without
  /// a limiter.
  void setGlobalBandwidthLimit(int? bytesPerSecond) {
    limiter?.setGlobalLimit(bytesPerSecond);
  }

  /// Changes the per-download bandwidth limit at runtime. No-op
  /// without a limiter.
  void setPerDownloadBandwidthLimit(int? bytesPerSecond) {
    limiter?.setPerDownloadLimit(bytesPerSecond);
  }

  /// Changes the concurrent-download limit and starts queued jobs when
  /// the limit grows.
  void setMaxConcurrent(int value) {
    _throwIfDisposed();
    if (value < 1) {
      throw ArgumentError.value(value, 'maxConcurrent', 'must be >= 1');
    }
    _maxConcurrent = value;
    _pump();
  }

  /// Cancels all work and releases the owned transport, if any.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final jobs = <_RunningJob>[
      ..._running.values,
      ..._pausedRunning.values,
    ];
    final pendingStarted = _pending.where((q) => q.started != null).toList();
    _running.clear();
    _pausedRunning.clear();
    _pending.clear();
    _starting.clear();
    for (final running in jobs) {
      unawaited(running.subscription.cancel());
      if (running.runStarted) {
        running.started.task.cancel();
      } else {
        unawaited(running.started.sink.close());
      }
    }
    for (final queued in pendingStarted) {
      unawaited(queued.subscription!.cancel());
      if (queued.runStarted) {
        queued.started!.task.cancel();
      } else {
        unawaited(queued.started!.sink.close());
      }
    }
    if (_ownsTransport) {
      _transport?.close();
    }
    await _events.close();
  }

  Future<ScheduledTask> _defaultTaskFactory(DownloadJob job) async {
    final transport = _transport ??= HttpTransport();
    final sink = await FileChunkSink.create(
      directory: job.directory,
      fileName: job.fileName,
      overwrite: job.overwrite,
    );
    final task = DownloadTask(
      transport: transport,
      sink: sink,
      url: Uri.parse(job.url),
      id: job.id,
      maxConnections: job.maxConnections,
      limiter: limiter,
      priority: job.priority,
    );
    return ScheduledTask(task, sink);
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    _pending.sort((a, b) {
      final byPriority = b.job.priority.compareTo(a.job.priority);
      if (byPriority != 0) {
        return byPriority;
      }
      return a.job.sequence.compareTo(b.job.sequence);
    });
    while (_running.length + _starting.length < _maxConcurrent) {
      final next = _nextStartableIndex();
      if (next == -1) {
        return;
      }
      final queued = _pending.removeAt(next);
      unawaited(_start(queued));
    }
  }

  /// Index of the first non-paused pending job that fits the
  /// remaining connection budget, or -1. A job that fits is started
  /// even when a higher-priority job ahead of it does not fit, so
  /// one large job cannot stall the whole queue; the large job
  /// starts once budget frees. When nothing is running or starting,
  /// the first non-paused job starts even if it alone exceeds the
  /// cap, so a single job can never deadlock the queue.
  int _nextStartableIndex() {
    final reserved = _reservedConnections;
    for (var i = 0; i < _pending.length; i++) {
      final queued = _pending[i];
      if (queued.paused) {
        continue;
      }
      if (reserved + queued.job.maxConnections <= _maxTotalConnections ||
          (_running.isEmpty && _starting.isEmpty)) {
        return i;
      }
    }
    return -1;
  }

  /// Connections reserved by running and starting jobs. Each job
  /// reserves its whole `maxConnections`: a task opens at most that
  /// many segment streams at once.
  int get _reservedConnections {
    var total = 0;
    for (final running in _running.values) {
      total += running.job.maxConnections;
    }
    for (final id in _starting) {
      total += _jobs[id]?.maxConnections ?? 0;
    }
    return total;
  }

  Future<void> _start(_QueuedJob queued) async {
    final job = queued.job;
    _starting.add(job.id);
    try {
      final started = queued.started;
      if (started == null) {
        final built = await _taskFactory(job);
        if (_disposed) {
          _starting.remove(job.id);
          await built.sink.close();
          return;
        }
        if (_cancelledWhileStarting.remove(job.id)) {
          _starting.remove(job.id);
          await built.sink.close();
          _markCancelled(job);
          _pump();
          return;
        }
        final subscription = built.task.events.listen(_onTaskEvent);
        if (_pausedWhileStarting.remove(job.id)) {
          _pausedRunning[job.id] = _RunningJob(
            job,
            built,
            subscription,
            runStarted: false,
          );
          _starting.remove(job.id);
          _pump();
          return;
        }
        _running[job.id] = _RunningJob(
          job,
          built,
          subscription,
          runStarted: true,
        );
        _starting.remove(job.id);
        unawaited(
          built.task.run().then(
            (info) => _onTaskDone(job, info),
            onError: (Object e) => _onTaskError(job, e),
          ),
        );
      } else {
        final running = _RunningJob(
          job,
          started,
          queued.subscription!,
          runStarted: queued.runStarted,
        );
        _running[job.id] = running;
        _starting.remove(job.id);
        if (queued.runStarted) {
          started.task.resume();
        } else {
          unawaited(
            started.task.run().then(
              (info) => _onTaskDone(job, info),
              onError: (Object e) => _onTaskError(job, e),
            ),
          );
        }
      }
    } catch (e) {
      _starting.remove(job.id);
      // A pause that landed while the task was being built must not
      // survive the failed start: the flag is consumed here, or the
      // next attempt for the same id would be parked as paused even
      // though nobody paused it.
      _pausedWhileStarting.remove(job.id);
      if (_cancelledWhileStarting.remove(job.id)) {
        _markCancelled(job);
      } else {
        _failJob(job, e);
      }
      _pump();
    }
  }

  void _onTaskEvent(DownloadEvent event) {
    if (_disposed) {
      return;
    }
    // The task reports completion before the scheduler finished the
    // sink (renamed the partial file to its final path): it emits both
    // stateChanged(completed) and the completed event. Hold both back;
    // _onTaskDone emits them once the file is final, so a consumer
    // acting on either can rely on the file existing.
    final forward = event.when(
      progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {
        final info = _infos[downloadId];
        if (info != null) {
          _infos[downloadId] = info.copyWith(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            bytesPerSecond: bytesPerSecond,
          );
        }
        return true;
      },
      stateChanged: (downloadId, status) {
        // The task sets its status to completed (and emits the
        // completed event) before the scheduler finished the sink.
        // Hold the completed state change back entirely — including
        // the downloads snapshot — so nothing ever reports a download
        // as completed before its file is final.
        if (status == DownloadStatus.completed) {
          return false;
        }
        final info = _infos[downloadId];
        if (info != null) {
          _infos[downloadId] = info.copyWith(status: status);
        }
        return true;
      },
      completed: (downloadId, filePath) {
        // Held back until _onTaskDone finishes the sink; the snapshot
        // must not claim completed before the file is final either.
        return false;
      },
      failed: (downloadId, code, message) {
        final info = _infos[downloadId];
        if (info != null) {
          _infos[downloadId] = info.copyWith(status: DownloadStatus.failed);
        }
        return true;
      },
    );
    if (forward) {
      _emit(event);
    }
  }

  Future<void> _onTaskDone(DownloadJob job, DownloadInfo info) async {
    final running = _running.remove(job.id) ?? _pausedRunning.remove(job.id);
    if (running != null) {
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          () => running.subscription.cancel(),
        ),
      );
    }
    if (info.status == DownloadStatus.completed) {
      final sink = running?.started.sink;
      if (sink is FileChunkSink) {
        try {
          await sink.finish();
        } catch (e) {
          _infos[job.id] = info.copyWith(
            status: DownloadStatus.failed,
            fileName: job.fileName,
          );
          _emit(
            DownloadEvent.failed(
              downloadId: job.id,
              code: 'finish-failed',
              message: e.toString(),
            ),
          );
          _pump();
          return;
        }
      }
      // Only now is the file final: report completed in the snapshot
      // and emit the terminal events together.
      _infos[job.id] = info.copyWith(fileName: job.fileName);
      _emit(
        DownloadEvent.stateChanged(
          downloadId: job.id,
          status: DownloadStatus.completed,
        ),
      );
      _emit(
        DownloadEvent.completed(
          downloadId: job.id,
          filePath: sink?.filePath ?? '',
        ),
      );
    } else {
      _infos[job.id] = info.copyWith(fileName: job.fileName);
    }
    _pump();
  }

  void _onTaskError(DownloadJob job, Object error) {
    final running = _running.remove(job.id) ?? _pausedRunning.remove(job.id);
    if (running != null) {
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          () => running.subscription.cancel(),
        ),
      );
    }
    final info = _infos[job.id];
    if (info != null) {
      _infos[job.id] = info.copyWith(status: DownloadStatus.failed);
    }
    _log.warning('Download ${job.id} failed: $error');
    _pump();
  }

  void _failJob(DownloadJob job, Object error) {
    final downloadError = error is DownloadError
        ? error
        : DownloadError('internal', error.toString());
    final info = _infos[job.id];
    if (info != null) {
      _infos[job.id] = info.copyWith(status: DownloadStatus.failed);
    }
    _emit(
      DownloadEvent.failed(
        downloadId: job.id,
        code: downloadError.code,
        message: downloadError.message,
      ),
    );
  }

  void _markCancelled(DownloadJob job) {
    final info = _infos[job.id];
    if (info != null) {
      _infos[job.id] = info.copyWith(status: DownloadStatus.cancelled);
    }
    _emit(
      DownloadEvent.stateChanged(
        downloadId: job.id,
        status: DownloadStatus.cancelled,
      ),
    );
  }

  void _emit(DownloadEvent event) {
    if (_disposed) {
      return;
    }
    _events.add(event);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('DownloadScheduler is disposed');
    }
  }

  _QueuedJob? _findPending(String id) {
    for (final queued in _pending) {
      if (queued.job.id == id) {
        return queued;
      }
    }
    return null;
  }
}
