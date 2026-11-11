import 'package:download_api/download_api.dart';
import 'package:test/test.dart';

void main() {
  group('DownloadInfo', () {
    test('round-trips through JSON', () {
      const info = DownloadInfo(
        id: 'd1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: DownloadStatus.queued,
        totalBytes: 1024,
      );
      final restored = DownloadInfo.fromJson(info.toJson());
      expect(restored, info);
    });

    test('copyWith changes only the given fields', () {
      const info = DownloadInfo(
        id: 'd1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: DownloadStatus.queued,
        totalBytes: 1024,
      );
      final updated = info.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: 512,
      );
      expect(updated.status, DownloadStatus.downloading);
      expect(updated.downloadedBytes, 512);
      expect(updated.id, 'd1');
    });
  });

  group('CreateDownloadRequest', () {
    test('round-trips the conflict policy through JSON', () {
      const request = CreateDownloadRequest(
        url: 'https://example.com/file.zip',
        destination: '/tmp/file.zip',
        conflictPolicy: FileConflictPolicy.rename,
      );
      final restored = CreateDownloadRequest.fromJson(request.toJson());
      expect(restored, request);
      expect(restored.conflictPolicy, FileConflictPolicy.rename);
    });

    test('defaults to no conflict policy', () {
      const request = CreateDownloadRequest(
        url: 'https://example.com/file.zip',
        destination: '/tmp/file.zip',
      );
      expect(request.conflictPolicy, isNull);
    });
  });

  group('DownloadEvent', () {
    test('progress event round-trips through JSON', () {
      const event = DownloadEvent.progress(
        downloadId: 'd1',
        downloadedBytes: 512,
        totalBytes: 1024,
        bytesPerSecond: 128,
      );
      final restored = DownloadEvent.fromJson(event.toJson());
      expect(restored, event);
    });
  });
}
