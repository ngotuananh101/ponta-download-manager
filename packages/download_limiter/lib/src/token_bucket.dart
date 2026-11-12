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
/// work is served fairly in arrival order. A request that does not
/// fit the tokens on hand yet does not block smaller requests behind
/// it: any queued request whose bytes fit the current tokens is
/// served, in queue order.
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
    if (_rate != null) {
      // Lowering the rate must also lower the burst and drop the
      // tokens accumulated above it: otherwise the old burst lets a
      // large request through immediately at the new low rate. (A
      // zero burst still takes the new rate as its initial burst.)
      _burst = _burst == 0 ? _rate! : min(_burst, _rate!);
      _tokens = min(_tokens, _burst.toDouble());
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
    // Skip-ahead: serve every queued request whose bytes fit the
    // tokens on hand, in queue order. A large request at the head
    // waits for the refill without blocking smaller ones behind it.
    var i = 0;
    while (i < _pending.length) {
      final request = _pending[i];
      if (_tokens >= request.bytes) {
        _tokens -= request.bytes;
        _pending.removeAt(i);
        request.completer.complete();
        // Do not advance i: the next request shifted into this slot.
      } else {
        i++;
      }
    }
    if (_pending.isNotEmpty) {
      // No remaining request fits yet; wake when the refill covers
      // the first remaining request's deficit.
      final first = _pending.first;
      final deficit = first.bytes - _tokens;
      final wait = Duration(
        microseconds: (deficit / _rate! * 1000000).ceil(),
      );
      _timer?.cancel();
      _timer = Timer(wait, _pump);
      return;
    }
    _timer?.cancel();
    _timer = null;
  }
}
