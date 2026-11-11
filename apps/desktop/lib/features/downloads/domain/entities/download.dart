import 'package:equatable/equatable.dart';

enum DownloadState { queued, downloading, paused, completed, failed, cancelled }

/// A download as the UI sees it. Engine-side types live in `download_api`;
/// this is the presentation-facing model for the downloads feature.
class Download extends Equatable {
  const Download({
    required this.id,
    required this.url,
    required this.fileName,
    required this.state,
    this.downloadedBytes = 0,
    required this.totalBytes,
    this.bytesPerSecond = 0,
    this.createdAt,
    this.filePath,
    this.errorMessage,
    this.priority = 0,
  });

  final String id;
  final String url;
  final String fileName;
  final DownloadState state;
  final int downloadedBytes;
  final int totalBytes;
  final int bytesPerSecond;

  /// When the download was added (the FDM "Added" column). Null for
  /// downloads created before this field existed.
  final DateTime? createdAt;

  /// Final on-disk destination. Null when unknown (e.g. a download
  /// created before this field existed). Used by the "Missing Files"
  /// filter.
  final String? filePath;

  /// Why the download failed, from the engine's failed event (e.g.
  /// ffmpeg/yt-dlp are missing for a stream). Null unless the
  /// download is failed. Shown as a tooltip on the Status cell.
  final String? errorMessage;

  /// Queue priority. Higher runs first; 0 is the default (normal).
  /// Shown as high / normal / low on the details panel's GENERAL tab.
  final int priority;

  double get progress =>
      totalBytes <= 0 ? 0 : downloadedBytes / totalBytes;

  Download copyWith({
    String? id,
    String? url,
    String? fileName,
    DownloadState? state,
    int? downloadedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    DateTime? createdAt,
    String? filePath,
    String? errorMessage,
    int? priority,
    bool clearErrorMessage = false,
  }) {
    return Download(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      state: state ?? this.state,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      createdAt: createdAt ?? this.createdAt,
      filePath: filePath ?? this.filePath,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      priority: priority ?? this.priority,
    );
  }

  @override
  List<Object?> get props => [
    id,
    url,
    fileName,
    state,
    downloadedBytes,
    totalBytes,
    bytesPerSecond,
    createdAt,
    filePath,
    errorMessage,
    priority,
  ];
}
