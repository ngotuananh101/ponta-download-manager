import 'dart:io';

import 'package:download_api/download_api.dart';

import 'download_record.dart';
import 'download_store.dart';

enum RecoveryAction { resume, restart, complete, unrecoverable }

class RecoveryDecision {
  const RecoveryDecision({
    required this.record,
    required this.action,
    required this.reason,
    this.segments = const [],
  });

  final DownloadRecord record;
  final RecoveryAction action;
  final String reason;

  /// Segments to resume from. Empty for restart, complete and
  /// unrecoverable decisions.
  final List<SegmentRecord> segments;
}

/// Startup reconciliation (§7.4): compares the stored checkpoints with
/// the files on disk and decides what to do with each non-terminal
/// download. Local only — the remote representation is validated by
/// the task itself (If-Range) when the download resumes.
class Recovery {
  Recovery(this.store);

  final DownloadStore store;

  List<RecoveryDecision> reconcile() {
    return store.listNonTerminal().map(_decide).toList();
  }

  RecoveryDecision _decide(DownloadRecord record) {
    if (record.url.isEmpty || record.fileName.isEmpty) {
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.unrecoverable,
        reason: 'record is missing its URL or file name',
      );
    }
    final finalFile = File(record.destinationPath);
    if (finalFile.existsSync()) {
      final size = finalFile.lengthSync();
      if (record.totalBytes < 0 || size == record.totalBytes) {
        store.upsertDownload(
          record.copyWith(
            status: DownloadStatus.completed,
            downloadedBytes: size,
          ),
        );
        return RecoveryDecision(
          record: record,
          action: RecoveryAction.complete,
          reason: 'final file already exists with the expected size',
        );
      }
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.restart,
        reason: 'final file exists but has an unexpected size',
      );
    }
    final partial = File(record.partialPath);
    if (!partial.existsSync()) {
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.restart,
        reason: 'partial file is missing',
      );
    }
    final size = partial.lengthSync();
    if (size == 0) {
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.restart,
        reason: 'partial file is empty',
      );
    }
    if (record.totalBytes >= 0 && size > record.totalBytes) {
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.restart,
        reason: 'partial file is larger than the download',
      );
    }
    final segments = store.getSegments(record.id);
    if (segments.isEmpty) {
      if (record.maxConnections <= 1) {
        return RecoveryDecision(
          record: record,
          action: RecoveryAction.resume,
          reason: 'single-stream partial file can resume from its size',
          segments: [
            SegmentRecord(
              downloadId: record.id,
              segmentId: 0,
              start: 0,
              end: null,
              downloaded: size,
            ),
          ],
        );
      }
      return RecoveryDecision(
        record: record,
        action: RecoveryAction.restart,
        reason: 'no segment checkpoint to resume from',
      );
    }
    for (final segment in segments) {
      if (segment.start + segment.downloaded > size) {
        return RecoveryDecision(
          record: record,
          action: RecoveryAction.restart,
          reason: 'segment checkpoint is inconsistent with the partial file',
        );
      }
      if (segment.end != null &&
          (segment.end! < segment.start ||
              (record.totalBytes >= 0 &&
                  segment.end! >= record.totalBytes))) {
        return RecoveryDecision(
          record: record,
          action: RecoveryAction.restart,
          reason: 'segment checkpoint is inconsistent with the download size',
        );
      }
    }
    return RecoveryDecision(
      record: record,
      action: RecoveryAction.resume,
      reason: 'partial file matches its segment checkpoint',
      segments: segments,
    );
  }
}
