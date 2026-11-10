import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:logging/logging.dart';

import 'download_record.dart';
import 'download_store.dart';

final _log = Logger('CheckpointWriter');

class _TrackedTask {
  _TrackedTask({
    required this.task,
    required this.directory,
    required this.fileName,
    required this.priority,
    required this.subscription,
    required this.record,
  });

  final DownloadTask task;
  final String directory;
  final String fileName;
  final int priority;
  final StreamSubscription<DownloadEvent> subscription;
  DownloadRecord record;
}

/// Persists download checkpoints to SQLite while tasks run (§9.2):
/// progress at a controlled interval, lifecycle transitions promptly.
class CheckpointWriter {
  CheckpointWriter(
    this.store, {
    this.checkpointInterval = const Duration(seconds: 1),
  });

  final DownloadStore store;
  final Duration checkpointInterval;

  final _tracked = <String, _TrackedTask>{};
  Timer? _timer;

  void track(
    DownloadTask task, {
    required String directory,
    required String fileName,
    int priority = 0,
  }) {
    if (_tracked.containsKey(task.id)) {
      return;
    }
    final record = DownloadRecord(
      id: task.id,
      url: task.url.toString(),
      fileName: fileName,
      directory: directory,
      status: DownloadStatus.queued,
      priority: priority,
      maxConnections: task.maxConnections,
    );
    store.upsertDownload(record);
    final subscription = task.events.listen((event) {
      final tracked = _tracked[task.id];
      if (tracked == null) {
        return;
      }
      event.when(
        progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {},
        stateChanged: (downloadId, status) {
          if (status == DownloadStatus.paused ||
              status == DownloadStatus.completed ||
              status == DownloadStatus.failed ||
              status == DownloadStatus.cancelled) {
            _write(tracked);
          }
          // The failed event still has to arrive with its error code,
          // so the subscription stays alive until then.
          if (status == DownloadStatus.completed ||
              status == DownloadStatus.cancelled) {
            _untrack(task.id);
          }
        },
        completed: (downloadId, filePath) {
          _write(tracked);
          _untrack(task.id);
        },
        failed: (downloadId, code, message) {
          tracked.record = tracked.record.copyWith(
            status: DownloadStatus.failed,
            errorCode: code,
            errorMessage: message,
          );
          _write(tracked);
          _untrack(task.id);
        },
      );
    });
    _tracked[task.id] = _TrackedTask(
      task: task,
      directory: directory,
      fileName: fileName,
      priority: priority,
      subscription: subscription,
      record: record,
    );
    _timer ??= Timer.periodic(checkpointInterval, (_) => _tick());
  }

  void flush() {
    for (final tracked in _tracked.values.toList()) {
      _write(tracked);
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    for (final tracked in _tracked.values.toList()) {
      await tracked.subscription.cancel();
    }
    flush();
    _tracked.clear();
  }

  void _tick() {
    for (final tracked in _tracked.values.toList()) {
      _write(tracked);
    }
    if (_tracked.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _write(_TrackedTask tracked) {
    final task = tracked.task;
    final record = tracked.record.copyWith(
      status: task.status,
      downloadedBytes: task.downloadedBytes,
      totalBytes: task.totalBytes,
      eTag: task.eTag,
      finalUrl: task.finalUrl?.toString(),
    );
    tracked.record = record;
    final segments = task.segments
        .map(
          (s) => SegmentRecord(
            downloadId: task.id,
            segmentId: s.segmentId,
            start: s.start,
            end: s.end,
            downloaded: s.downloaded,
          ),
        )
        .toList();
    store.saveCheckpoint(record, segments);
    _log.fine(
      'Checkpoint ${task.id}: ${record.status.name} '
      '${record.downloadedBytes}/${record.totalBytes}',
    );
  }

  void _untrack(String id) {
    final tracked = _tracked.remove(id);
    if (tracked == null) {
      return;
    }
    unawaited(tracked.subscription.cancel());
    if (_tracked.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
