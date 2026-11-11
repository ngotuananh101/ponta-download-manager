import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/features/downloads/data/services/thumbnail_service.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

Download _download({
  required String fileName,
  required DownloadState state,
  String? filePath,
}) {
  return Download(
    id: 'dl-1',
    url: 'http://127.0.0.1:9/$fileName',
    fileName: fileName,
    state: state,
    downloadedBytes: 100,
    totalBytes: 100,
    filePath: filePath,
  );
}

void main() {
  group('ThumbnailService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-thumb-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns the image file itself for a completed image', () async {
      final file = File(p.join(tempDir.path, 'pic.png'));
      await file.writeAsBytes([0, 1, 2, 3]);
      final service = ThumbnailService(cacheDir: tempDir.path);
      expect(
        await service.thumbnailFor(
          _download(
            fileName: 'pic.png',
            state: DownloadState.completed,
            filePath: file.path,
          ),
        ),
        file.path,
      );
    });

    test('returns null for a non-media file', () async {
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes([0, 1, 2, 3]);
      final service = ThumbnailService(cacheDir: tempDir.path);
      expect(
        await service.thumbnailFor(
          _download(
            fileName: 'f.bin',
            state: DownloadState.completed,
            filePath: file.path,
          ),
        ),
        isNull,
      );
    });

    test('returns null while a video is still downloading', () async {
      final file = File(p.join(tempDir.path, 'clip.mp4'));
      await file.writeAsBytes([0, 1, 2, 3]);
      final service = ThumbnailService(cacheDir: tempDir.path);
      expect(
        await service.thumbnailFor(
          _download(
            fileName: 'clip.mp4',
            state: DownloadState.downloading,
            filePath: file.path,
          ),
        ),
        isNull,
      );
    });

    test('returns null when the file is gone', () async {
      final service = ThumbnailService(cacheDir: tempDir.path);
      expect(
        await service.thumbnailFor(
          _download(
            fileName: 'clip.mp4',
            state: DownloadState.completed,
            filePath: p.join(tempDir.path, 'clip.mp4'),
          ),
        ),
        isNull,
      );
    });

    test('extracts a video frame with ffmpeg and caches it', () async {
      final video = File(p.join(tempDir.path, 'clip.mp4'));
      await video.writeAsBytes([0, 1, 2, 3]);
      final calls = <List<String>>[];
      Future<ProcessResult> fakeRun(
        List<String> args, {
        Duration? timeout,
      }) async {
        calls.add(args);
        await File(args.last).create(recursive: true);
        return ProcessResult(0, 0, '', '');
      }

      final service = ThumbnailService(
        ffmpegPath: '/usr/bin/ffmpeg',
        cacheDir: p.join(tempDir.path, 'thumbs'),
        runProcess: fakeRun,
      );
      final download = _download(
        fileName: 'clip.mp4',
        state: DownloadState.completed,
        filePath: video.path,
      );
      final first = await service.thumbnailFor(download);
      expect(first, isNotNull);
      expect(first, endsWith('.jpg'));
      expect(await File(first!).exists(), isTrue);
      expect(calls.length, 1);
      expect(calls.single, contains(video.path));
      final second = await service.thumbnailFor(download);
      expect(second, first);
      expect(calls.length, 1);
    });

    test('returns null when ffmpeg fails on both seeks', () async {
      final video = File(p.join(tempDir.path, 'clip.mp4'));
      await video.writeAsBytes([0, 1, 2, 3]);
      final calls = <List<String>>[];
      Future<ProcessResult> failingRun(
        List<String> args, {
        Duration? timeout,
      }) async {
        calls.add(args);
        return ProcessResult(0, 1, '', 'boom');
      }

      final service = ThumbnailService(
        ffmpegPath: '/usr/bin/ffmpeg',
        cacheDir: p.join(tempDir.path, 'thumbs'),
        runProcess: failingRun,
      );
      expect(
        await service.thumbnailFor(
          _download(
            fileName: 'clip.mp4',
            state: DownloadState.completed,
            filePath: video.path,
          ),
        ),
        isNull,
      );
      expect(calls.length, 2);
    });
  });
}
