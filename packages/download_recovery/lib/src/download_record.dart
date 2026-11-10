import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

/// One download as stored in SQLite (docs/architecture.md §9.1).
class DownloadRecord {
  DownloadRecord({
    required this.id,
    required this.url,
    required this.fileName,
    required this.directory,
    this.status = DownloadStatus.queued,
    this.downloadedBytes = 0,
    this.totalBytes = -1,
    this.eTag,
    this.lastModified,
    this.finalUrl,
    this.supportsRange,
    this.priority = 0,
    this.maxConnections = 4,
    this.errorCode,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String url;
  final String fileName;
  final String directory;
  final DownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String? eTag;
  final String? lastModified;
  final String? finalUrl;
  final bool? supportsRange;
  final int priority;
  final int maxConnections;
  final String? errorCode;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get destinationPath => p.join(directory, fileName);
  String get partialPath => '$destinationPath.partial';

  DownloadRecord copyWith({
    String? id,
    String? url,
    String? fileName,
    String? directory,
    DownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    String? eTag,
    String? lastModified,
    String? finalUrl,
    bool? supportsRange,
    int? priority,
    int? maxConnections,
    String? errorCode,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DownloadRecord(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      directory: directory ?? this.directory,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      eTag: eTag ?? this.eTag,
      lastModified: lastModified ?? this.lastModified,
      finalUrl: finalUrl ?? this.finalUrl,
      supportsRange: supportsRange ?? this.supportsRange,
      priority: priority ?? this.priority,
      maxConnections: maxConnections ?? this.maxConnections,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadRecord &&
        other.id == id &&
        other.url == url &&
        other.fileName == fileName &&
        other.directory == directory &&
        other.status == status &&
        other.downloadedBytes == downloadedBytes &&
        other.totalBytes == totalBytes &&
        other.eTag == eTag &&
        other.lastModified == lastModified &&
        other.finalUrl == finalUrl &&
        other.supportsRange == supportsRange &&
        other.priority == priority &&
        other.maxConnections == maxConnections &&
        other.errorCode == errorCode &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        id,
        url,
        fileName,
        directory,
        status,
        downloadedBytes,
        totalBytes,
        eTag,
        lastModified,
        finalUrl,
        supportsRange,
        priority,
        maxConnections,
        errorCode,
        errorMessage,
      );
}

/// Checkpointed progress of one segment.
class SegmentRecord {
  const SegmentRecord({
    required this.downloadId,
    required this.segmentId,
    required this.start,
    required this.end,
    required this.downloaded,
  });

  final String downloadId;
  final int segmentId;
  final int start;
  final int? end;
  final int downloaded;

  int? get length => end == null ? null : end! - start + 1;
  bool get isComplete => length != null && downloaded >= length!;

  SegmentRecord copyWith({
    String? downloadId,
    int? segmentId,
    int? start,
    int? end,
    int? downloaded,
  }) {
    return SegmentRecord(
      downloadId: downloadId ?? this.downloadId,
      segmentId: segmentId ?? this.segmentId,
      start: start ?? this.start,
      end: end ?? this.end,
      downloaded: downloaded ?? this.downloaded,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SegmentRecord &&
        other.downloadId == downloadId &&
        other.segmentId == segmentId &&
        other.start == start &&
        other.end == end &&
        other.downloaded == downloaded;
  }

  @override
  int get hashCode =>
      Object.hash(downloadId, segmentId, start, end, downloaded);
}
