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

    test('tags default to empty and round-trip through JSON', () {
      const info = DownloadInfo(
        id: 'd1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: DownloadStatus.queued,
        totalBytes: 1024,
        tags: ['iso', 'music'],
      );
      final restored = DownloadInfo.fromJson(info.toJson());
      expect(restored, info);
      expect(restored.tags, ['iso', 'music']);
      const untagged = DownloadInfo(
        id: 'd1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: DownloadStatus.queued,
        totalBytes: 1024,
      );
      expect(untagged.tags, isEmpty);
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

    test('round-trips cookie and referrer through JSON', () {
      const request = CreateDownloadRequest(
        url: 'https://example.com/file.zip',
        destination: '/tmp/file.zip',
        cookie: 'session=abc; theme=dark',
        referrer: 'https://example.com/page',
      );
      final restored = CreateDownloadRequest.fromJson(request.toJson());
      expect(restored, request);
      expect(restored.cookie, 'session=abc; theme=dark');
      expect(restored.referrer, 'https://example.com/page');
    });

    test('defaults to no cookie or referrer', () {
      const request = CreateDownloadRequest(
        url: 'https://example.com/file.zip',
        destination: '/tmp/file.zip',
      );
      expect(request.cookie, isNull);
      expect(request.referrer, isNull);
    });
    test('round-trips ytDlpFormat through JSON', () {
      const request = CreateDownloadRequest(
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        destination: '/tmp/video.mp4',
        ytDlpFormat: '137+bestaudio',
      );
      final restored = CreateDownloadRequest.fromJson(request.toJson());
      expect(restored, request);
      expect(restored.ytDlpFormat, '137+bestaudio');
    });

    test('defaults to no ytDlpFormat', () {
      const request = CreateDownloadRequest(
        url: 'https://example.com/file.zip',
        destination: '/tmp/file.zip',
      );
      expect(request.ytDlpFormat, isNull);
    });
  });

  group('YtDlpProbeResult', () {
    test('round-trips a supported result with formats through JSON', () {
      const result = YtDlpProbeResult(
        supported: true,
        title: 'Test video',
        thumbnail: 'https://example.com/thumb.jpg',
        durationSeconds: 360,
        formats: [
          YtDlpFormat(
            formatId: '137',
            ext: 'mp4',
            resolution: '1920x1080',
            width: 1920,
            height: 1080,
            filesize: 123456789,
            vcodec: 'avc1.640028',
            acodec: 'none',
            fps: 30,
          ),
          YtDlpFormat(
            formatId: '140',
            ext: 'm4a',
            vcodec: 'none',
            acodec: 'mp4a.40.2',
            filesizeApprox: 1234567,
            note: 'audio only',
          ),
        ],
      );
      final restored = YtDlpProbeResult.fromJson(result.toJson());
      expect(restored, result);
      expect(restored.formats, hasLength(2));
      expect(restored.formats.first.formatId, '137');
      expect(restored.formats.first.filesize, 123456789);
      expect(restored.formats.last.acodec, 'mp4a.40.2');
    });

    test('round-trips an unsupported result through JSON', () {
      const result = YtDlpProbeResult(
        supported: false,
        errorCode: 'yt-dlp-unsupported',
        errorMessage: 'Unsupported URL',
      );
      final restored = YtDlpProbeResult.fromJson(result.toJson());
      expect(restored, result);
      expect(restored.supported, isFalse);
      expect(restored.formats, isEmpty);
    });

    test('formats default to empty', () {
      const result = YtDlpProbeResult(supported: true, title: 'T');
      expect(result.formats, isEmpty);
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
