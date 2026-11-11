import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_external/download_external.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _successScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo "[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30"
echo "[download]  50.0% of  100.00MiB at  2.00MiB/s ETA 00:25"
echo "[download] 100% of  100.00MiB in 00:01"
mkdir -p "$(dirname "$final")"
touch "$final"
echo "$final"
exit 0
''';

const _failureScript = r'''#!/bin/sh
echo "ERROR: unable to download video data" >&2
exit 1
''';

const _slowScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo "[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30"
mkdir -p "$(dirname "$final")"
touch "$final.part"
sleep 10
echo "$final"
exit 0
''';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdm-ytdlp-');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<String> makeFake(String name, String script) async {
    final file = File(p.join(tmp.path, name));
    await file.writeAsString(script);
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  test('a successful run emits progress and completed with the final path',
      () async {
    final fake = await makeFake('yt-dlp', _successScript);
    final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
    final downloader = YtDlpDownloader(
      ytDlpPath: fake,
      ffmpegDir: tmp.path,
    );
    final events = <DownloadEvent>[];
    final done = Completer<void>();
    downloader
        .start(
          downloadId: 'dl-1',
          url: 'https://example.com/live.m3u8',
          outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
        )
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 10));
    expect(events.length, 4);
    final progresses = events.whereType<DownloadProgress>().toList();
    expect(progresses.length, 3);
    expect(progresses.first.downloadedBytes, (100 * 1024 * 1024 * 0.1).round());
    expect(progresses.first.totalBytes, 100 * 1024 * 1024);
    expect(progresses.last.downloadedBytes, 100 * 1024 * 1024);
    final completed = events.whereType<DownloadCompleted>().single;
    expect(completed.downloadId, 'dl-1');
    expect(completed.filePath, p.join(outDir.path, 'live.mp4'));
    expect(File(completed.filePath).existsSync(), isTrue);
  });

  test('a failing run emits failed with the stderr message', () async {
    final fake = await makeFake('yt-dlp', _failureScript);
    final downloader = YtDlpDownloader(
      ytDlpPath: fake,
      ffmpegDir: tmp.path,
    );
    final events = <DownloadEvent>[];
    final done = Completer<void>();
    downloader
        .start(
          downloadId: 'dl-1',
          url: 'https://example.com/live.m3u8',
          outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
        )
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 10));
    expect(events.length, 1);
    final failed = events.single as DownloadFailed;
    expect(failed.code, 'yt-dlp-failed');
    expect(failed.message, contains('unable to download video data'));
  });

  test('a missing binary emits failed with a spawn error', () async {
    final downloader = YtDlpDownloader(
      ytDlpPath: p.join(tmp.path, 'no-such-yt-dlp'),
      ffmpegDir: tmp.path,
    );
    final events = <DownloadEvent>[];
    final done = Completer<void>();
    downloader
        .start(
          downloadId: 'dl-1',
          url: 'https://example.com/live.m3u8',
          outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
        )
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 10));
    expect(events.length, 1);
    final failed = events.single as DownloadFailed;
    expect(failed.code, 'yt-dlp-spawn-failed');
  });

  test('pause kills the process and emits paused, keeping the partial',
      () async {
    final fake = await makeFake('yt-dlp', _slowScript);
    final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
    final downloader = YtDlpDownloader(
      ytDlpPath: fake,
      ffmpegDir: tmp.path,
    );
    final events = <DownloadEvent>[];
    final done = Completer<void>();
    final stream = downloader.start(
      downloadId: 'dl-1',
      url: 'https://example.com/live.m3u8',
      outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
    );
    stream.listen(events.add, onDone: done.complete);
    // Wait for the first progress event, then pause.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await downloader.pause('dl-1');
    await done.future.timeout(const Duration(seconds: 10));
    expect(events.any((e) => e is DownloadProgress), isTrue);
    final last = events.last;
    expect(last, isA<DownloadStateChanged>());
    expect((last as DownloadStateChanged).status, DownloadStatus.paused);
    expect(File(p.join(outDir.path, 'live.mp4.part')).existsSync(), isTrue);
    expect(File(p.join(outDir.path, 'live.mp4')).existsSync(), isFalse);
  });

  test('cancel kills the process, deletes the output and emits cancelled',
      () async {
    final fake = await makeFake('yt-dlp', _slowScript);
    final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
    final downloader = YtDlpDownloader(
      ytDlpPath: fake,
      ffmpegDir: tmp.path,
    );
    final events = <DownloadEvent>[];
    final done = Completer<void>();
    final stream = downloader.start(
      downloadId: 'dl-1',
      url: 'https://example.com/live.m3u8',
      outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
    );
    stream.listen(events.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await downloader.cancel('dl-1');
    await done.future.timeout(const Duration(seconds: 10));
    final last = events.last;
    expect(last, isA<DownloadStateChanged>());
    expect((last as DownloadStateChanged).status, DownloadStatus.cancelled);
    expect(File(p.join(outDir.path, 'live.mp4.part')).existsSync(), isFalse);
    expect(File(p.join(outDir.path, 'live.mp4')).existsSync(), isFalse);
  });

  test('starting the same download twice throws', () async {
    final fake = await makeFake('yt-dlp', _slowScript);
    final downloader = YtDlpDownloader(
      ytDlpPath: fake,
      ffmpegDir: tmp.path,
    );
    downloader.start(
      downloadId: 'dl-1',
      url: 'https://example.com/live.m3u8',
      outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
    ).listen((_) {}, onDone: () {});
    expect(
      () => downloader.start(
        downloadId: 'dl-1',
        url: 'https://example.com/live.m3u8',
        outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
      ),
      throwsStateError,
    );
    await downloader.cancel('dl-1');
  });
}
