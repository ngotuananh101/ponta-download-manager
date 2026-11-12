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
///
/// A task reports completion before its sink is renamed to the final
/// file, so the writer never persists completed from task events
/// alone: it keeps the download as downloading with full bytes until
/// complete() finalizes it (called from the scheduler's post-rename
/// completed event), or fail() when finalization fails.
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
    // The record usually already exists (createDownload stored
    // it, possibly with mirrors and tags): keep it. A fresh record
    // here would wipe them the moment the task starts, so a mirror
    // added before the first attempt would never be tried.
    final existing = store.getDownload(task.id);
    final record = existing ??
        DownloadRecord(
          id: task.id,
          url: task.url.toString(),
          fileName: fileName,
          directory: directory,
          status: DownloadStatus.queued,
          priority: priority,
          maxConnections: task.maxConnections,
        );
    if (existing == null) {
      store.upsertDownload(record);
    }
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
          // Completed does not untrack: the task reports completion
          // before the sink rename, so the store must not say
          // completed yet. complete() finalizes it once the final
          // file exists, and _write keeps the status downloading
          // until then.
          if (status == DownloadStatus.cancelled) {
            _untrack(task.id);
          }
        },
        completed: (downloadId, filePath) {
          // Also pre-rename: only persist the final bytes, never the
          // completed status. See complete().
          _write(tracked);
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

  /// Finalizes a tracked download as completed. Call only after its
  /// final file exists: the scheduler emits its completed events
  /// after the sink rename, while the task's own completed events
  /// arrive before it. No-op when the download is not tracked.
  void complete(String downloadId) {
    final tracked = _tracked[downloadId];
    if (tracked == null) {
      return;
    }
    _writeStatus(tracked, DownloadStatus.completed);
    _untrack(downloadId);
  }

  /// Marks a tracked download failed, e.g. when finalization fails
  /// after the task reported completion (the sink rename failed).
  /// No-op when the download is not tracked.
  void fail(String downloadId, String code, String message) {
    final tracked = _tracked[downloadId];
    if (tracked == null) {
      return;
    }
    tracked.record = tracked.record.copyWith(
      errorCode: code,
      errorMessage: message,
    );
    _writeStatus(tracked, DownloadStatus.failed);
    _untrack(downloadId);
  }

  void _write(_TrackedTask tracked) {
    _writeStatus(tracked, _persistedStatus(tracked.task.status));
  }

  /// The status that may be persisted from task state alone. A task
  /// reports completion before the sink rename, so completed is kept
  /// as downloading (with full bytes) until complete() finalizes it.
  DownloadStatus _persistedStatus(DownloadStatus status) {
    return status == DownloadStatus.completed
        ? DownloadStatus.downloading
        : status;
  }

  void _writeStatus(_TrackedTask tracked, DownloadStatus status) {
    final task = tracked.task;
    // Re-read the stored record first: tags, mirrors or priority may
    // have changed since track() (addTag and setPriority write
    // straight to the store), and a checkpoint must not overwrite
    // them with the snapshot taken when tracking started. Only the
    // fields the writer itself owns come from the task and the
    // tracked record.
    final stored = store.getDownload(task.id);
    final base = stored ?? tracked.record;
    final record = base.copyWith(
      status: status,
      downloadedBytes: task.downloadedBytes,
      totalBytes: task.totalBytes,
      eTag: task.eTag,
      finalUrl: task.finalUrl?.toString(),
      errorCode: tracked.record.errorCode,
      errorMessage: tracked.record.errorMessage,
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
