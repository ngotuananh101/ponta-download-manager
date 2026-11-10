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
  });

  final String id;
  final String url;
  final String fileName;
  final DownloadState state;
  final int downloadedBytes;
  final int totalBytes;
  final int bytesPerSecond;

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
  }) {
    return Download(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      state: state ?? this.state,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
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
  ];
}
