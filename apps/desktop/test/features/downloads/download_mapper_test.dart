import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/datasources/download_mapper.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

void main() {
  test('downloadFromInfo carries createdAt through', () {
    final createdAt = DateTime(2026, 11, 10, 22, 29);
    final info = DownloadInfo(
      id: 'dl-1',
      url: 'https://example.com/f.bin',
      fileName: 'f.bin',
      status: DownloadStatus.completed,
      downloadedBytes: 100,
      totalBytes: 100,
      bytesPerSecond: 0,
      createdAt: createdAt,
    );
    final download = downloadFromInfo(info);
    expect(download.createdAt, createdAt);
    expect(download.state, DownloadState.completed);
  });

  test('downloadFromInfo leaves createdAt null when the info has none',
      () {
    const info = DownloadInfo(
      id: 'dl-1',
      url: 'https://example.com/f.bin',
      fileName: 'f.bin',
      status: DownloadStatus.queued,
      downloadedBytes: 0,
      totalBytes: 1000,
    );
    expect(downloadFromInfo(info).createdAt, isNull);
  });
}
