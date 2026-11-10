import 'dart:async';

import 'token_bucket.dart';

/// Two-level bandwidth limiting (docs/architecture.md §10): a global
/// bucket for the whole application plus one bucket per download.
/// [acquire] waits on both, so neither limit can be exceeded. Limits
/// can change at runtime without restarting downloads. The limiter
/// is owned by its caller, never by the scheduler.
class BandwidthLimiter {
  BandwidthLimiter({
    int? globalBytesPerSecond,
    int? perDownloadBytesPerSecond,
  })  : _global = TokenBucket(rateBytesPerSecond: globalBytesPerSecond),
        _defaultPerDownloadRate = perDownloadBytesPerSecond;

  final TokenBucket _global;
  int? _defaultPerDownloadRate;
  final _perDownload = <String, TokenBucket>{};
  final _overrides = <String>{};

  Future<void> acquire(
    String downloadId,
    int bytes, {
    int priority = 0,
  }) {
    final perDownload = _perDownload.putIfAbsent(
      downloadId,
      () => TokenBucket(rateBytesPerSecond: _defaultPerDownloadRate),
    );
    return Future.wait([
      perDownload.acquire(bytes, priority: priority),
      _global.acquire(bytes, priority: priority),
    ]);
  }

  void setGlobalLimit(int? bytesPerSecond) {
    _global.setRate(bytesPerSecond);
  }

  void setPerDownloadLimit(int? bytesPerSecond) {
    _defaultPerDownloadRate = bytesPerSecond;
    for (final entry in _perDownload.entries) {
      if (!_overrides.contains(entry.key)) {
        entry.value.setRate(bytesPerSecond);
      }
    }
  }

  void setDownloadLimit(String downloadId, int? bytesPerSecond) {
    _overrides.add(downloadId);
    _perDownload
        .putIfAbsent(
          downloadId,
          () => TokenBucket(rateBytesPerSecond: bytesPerSecond),
        )
        .setRate(bytesPerSecond);
  }

  void removeDownload(String downloadId) {
    _overrides.remove(downloadId);
    _perDownload.remove(downloadId)?.dispose();
  }

  void dispose() {
    _global.dispose();
    for (final bucket in _perDownload.values) {
      bucket.dispose();
    }
    _perDownload.clear();
    _overrides.clear();
  }
}
