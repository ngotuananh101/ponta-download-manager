import 'dart:async';
import 'dart:math';

/// A queued request waiting for tokens.
class _PendingRequest {
  _PendingRequest({
    required this.bytes,
    required this.priority,
    required this.sequence,
  });

  final int bytes;
  final int priority;
  final int sequence;
  final completer = Completer<void>();
}

/// A token bucket (docs/architecture.md §10). Tokens refill at
/// [rateBytesPerSecond], capped at the burst (default: one second of
/// rate). Requests wait in a queue ordered by priority desc, arrival
/// asc, so higher-priority work is served first and same-priority
/// work is served fairly in arrival order.
///
/// A null rate is unlimited: requests pass immediately.
class TokenBucket {
  TokenBucket({int? rateBytesPerSecond, int? burstBytes})
      : _rate = rateBytesPerSecond,
        _burst = burstBytes ?? rateBytesPerSecond ?? 0 {
    _tokens = _burst.toDouble();
    _stopwatch.start();
  }

  int? _rate;
  int _burst;
  double _tokens = 0;
  final _stopwatch = Stopwatch();
  var _last = Duration.zero;
  final _pending = <_PendingRequest>[];
  var _sequence = 0;
  Timer? _timer;

  int? get rateBytesPerSecond => _rate;
  int get burstBytes => _burst;

  void setRate(int? rateBytesPerSecond) {
    _refill();
    _rate = rateBytesPerSecond;
    if (_rate != null && _burst == 0) {
      _burst = _rate!;
    }
    _pump();
  }

  void setBurst(int burstBytes) {
    _burst = burstBytes;
    if (_tokens > _burst) {
      _tokens = _burst.toDouble();
    }
    _pump();
  }

  Future<void> acquire(int bytes, {int priority = 0}) {
    if (_rate == null) {
      return Future.value();
    }
    _refill();
    if (_pending.isEmpty && _tokens >= bytes) {
      _tokens -= bytes;
      return Future.value();
    }
    final request = _PendingRequest(
      bytes: bytes,
      priority: priority,
      sequence: _sequence++,
    );
    var index = _pending.length;
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i].priority < priority) {
        index = i;
        break;
      }
    }
    _pending.insert(index, request);
    _pump();
    return request.completer.future;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending.toList();
    _pending.clear();
    for (final request in pending) {
      request.completer.completeError(
        StateError('TokenBucket disposed'),
      );
    }
  }

  void _refill() {
    if (_rate == null) {
      return;
    }
    final now = _stopwatch.elapsed;
    final dt = (now - _last).inMicroseconds / 1000000;
    _last = now;
    if (dt <= 0) {
      return;
    }
    // Tokens may accumulate past the burst when a pending request is
    // larger than the burst; otherwise it could never be served.
    var cap = _burst.toDouble();
    for (final request in _pending) {
      cap = max(cap, request.bytes.toDouble());
    }
    _tokens = min(cap, _tokens + _rate! * dt);
  }

  void _pump() {
    if (_rate == null) {
      final pending = _pending.toList();
      _pending.clear();
      _timer?.cancel();
      _timer = null;
      for (final request in pending) {
        request.completer.complete();
      }
      return;
    }
    _refill();
    while (_pending.isNotEmpty) {
      final head = _pending.first;
      if (_tokens >= head.bytes) {
        _tokens -= head.bytes;
        _pending.removeAt(0);
        head.completer.complete();
      } else {
        final deficit = head.bytes - _tokens;
        final wait = Duration(
          microseconds: (deficit / _rate! * 1000000).ceil(),
        );
        _timer?.cancel();
        _timer = Timer(wait, _pump);
        return;
      }
    }
    _timer?.cancel();
    _timer = null;
  }
}
