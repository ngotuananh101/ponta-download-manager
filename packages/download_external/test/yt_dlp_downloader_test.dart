import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_external/download_external.dart';
import 'package:download_external/src/yt_dlp_cookies.dart';
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

const _unrelatedOnlyScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
stem=$(printf '%s' "$out" | sed 's/\.%(ext)s//')
mkdir -p "$(dirname "$stem")"
touch "$stem-notes.txt"
exit 0
''';

// Mirrors a `<video>+bestaudio` yt-dlp run: one plan line, then two
// streams, each printing its own 0→100% and finishing before the next
// one starts. This is the shape that used to show as "100%, then the
// download starts again".
const _twoStreamScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo 'PDMPLAN|["137", "140"]|[5000000, 1000000]|[]|137+140|NA|6000000'
echo 'PDMPROGRESS|downloading|137|500000|5000000|NA|1000000'
echo 'PDMPROGRESS|downloading|137|2500000|5000000|NA|1000000'
echo 'PDMPROGRESS|downloading|137|5000000|5000000|NA|1000000'
echo 'PDMPROGRESS|finished|137|5000000|5000000|NA|NA'
echo 'PDMPROGRESS|downloading|140|100000|1000000|NA|500000'
echo 'PDMPROGRESS|downloading|140|1000000|1000000|NA|500000'
echo 'PDMPROGRESS|finished|140|1000000|1000000|NA|NA'
mkdir -p "$(dirname "$final")"
touch "$final"
echo "$final"
exit 0
''';

// The same two streams with the plan line missing (it races the first
// progress line in practice): the run total is unknown, but the
// percent still must not drop back when the second stream starts.
const _twoStreamNoPlanScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo 'PDMPROGRESS|downloading|137|2500000|5000000|NA|1000000'
echo 'PDMPROGRESS|finished|137|5000000|5000000|NA|NA'
echo 'PDMPROGRESS|downloading|140|100000|1000000|NA|500000'
echo 'PDMPROGRESS|downloading|140|1000000|1000000|NA|500000'
echo 'PDMPROGRESS|finished|140|1000000|1000000|NA|NA'
mkdir -p "$(dirname "$final")"
touch "$final"
echo "$final"
exit 0
''';


/// A fake [Process] driven by the test: stdout/stderr lines are fed
/// through [addStdout]/[addStderr], [exitCode] completes when
/// [completeExit] is called, and [kill] is observable via [killed].
/// Events added before the downloader attaches its listeners are
/// buffered by the single-subscription controllers.
class _FakeProcess implements Process {
  _FakeProcess();

  final _stdoutController = StreamController<List<int>>();
  final _stderrController = StreamController<List<int>>();
  final _exitCode = Completer<int>();
  bool killed = false;

  void addStdout(String line) {
    _stdoutController.add(utf8.encode('$line\n'));
  }

  void addStderr(String line) {
    _stderrController.add(utf8.encode('$line\n'));
  }

  void closeStreams() {
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
  }

  void completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 1234;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    completeExit(143);
    return true;
  }
}

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

  test('passes --progress so progress is not suppressed by --print',
      () async {
    final argvFile = File(p.join(tmp.path, 'argv.txt'));
    final script = File(p.join(tmp.path, 'yt-dlp-argv'));
    await script.writeAsString(
      '#!/bin/sh\n'
      'printf "%s\\n" "\$@" > ${argvFile.path}\n'
      'exit 0\n',
    );
    await Process.run('chmod', ['+x', script.path]);
    final downloader = YtDlpDownloader(
      ytDlpPath: script.path,
      ffmpegDir: tmp.path,
    );
    final events = downloader.start(
      downloadId: 'dl-argv',
      url: 'https://example.com/live.m3u8',
      outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
    );
    await events.toList();
    final argv = (await argvFile.readAsString()).split('\n');
    expect(argv, contains('--progress'));
    expect(argv, contains('--print'));
    // The machine-readable progress line and the plan line: without
    // them one run of two streams reports each stream's own 0→100%.
    expect(argv, contains(ytDlpProgressTemplate));
    expect(argv, contains(ytDlpStreamPlanPrint));
  });

  test('two streams render as one monotonic run that completes', () async {
    final fake = await makeFake('yt-dlp', _twoStreamScript);
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
          url: 'https://example.com/watch?v=abc',
          outputTemplate: p.join(outDir.path, 'fake.%(ext)s'),
          format: '137+bestaudio',
        )
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 10));

    final progresses = events.whereType<DownloadProgress>().toList();
    expect(progresses, isNotEmpty);
    // Percent never goes backwards, never claims 100% before done.
    var last = 0.0;
    for (final p in progresses) {
      final percent = p.totalBytes <= 0
          ? 0.0
          : p.downloadedBytes * 100 / p.totalBytes;
      expect(percent, greaterThanOrEqualTo(last - 0.01));
      expect(p.downloadedBytes, lessThanOrEqualTo(p.totalBytes));
      last = percent;
    }
    // One total for the whole run (both streams), not the last one's,
    // and the run is only marked done by the completed event.
    expect(progresses.last.totalBytes, 6000000);
    expect(progresses.last.downloadedBytes, 6000000);
    // The two per-stream "finished" lines may both land at 100%; what
    // must not happen is a later *downloading* line dropping below the
    // previous one.
    final downloading =
        events.whereType<DownloadProgress>().toList(growable: false);
    expect(downloading.length, progresses.length);
    expect(events.whereType<DownloadCompleted>().length, 1);
  });

  test('two streams without a plan never restart at 0%', () async {
    final fake = await makeFake('yt-dlp', _twoStreamNoPlanScript);
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
          url: 'https://example.com/watch?v=abc',
          outputTemplate: p.join(outDir.path, 'fake.%(ext)s'),
        )
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 10));

    final progresses = events.whereType<DownloadProgress>().toList();
    // Until the first stream finishes, the row shows that stream's own
    // percent, monotonic.
    var lastPercent = 0.0;
    var finishedFirst = false;
    var lastBytes = 0;
    for (final p in progresses) {
      if (p.totalBytes < 0) {
        // After the first stream finished the run total is unknowable
        // without a plan: bytes keep counting, the percent rests at 0.
        expect(finishedFirst, isTrue);
        expect(p.downloadedBytes, greaterThanOrEqualTo(lastBytes));
        lastBytes = p.downloadedBytes;
        continue;
      }
      final percent = p.downloadedBytes * 100 / p.totalBytes;
      expect(percent, greaterThanOrEqualTo(lastPercent - 0.01));
      lastPercent = percent;
      lastBytes = p.downloadedBytes;
      // The stream's own 100% is reported as 99: only the completed
      // event closes the run.
      if (percent >= 99) {
        finishedFirst = true;
      }
    }
    expect(finishedFirst, isTrue);
    final last = progresses.last;
    expect(last.totalBytes, -1);
    // Both streams' bytes are carried once they are in.
    expect(last.downloadedBytes, 6000000);
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

  test('deleteOutput deletes only this download\'s own files', () {
    final downloader = YtDlpDownloader(
      ytDlpPath: p.join(tmp.path, 'no-such-yt-dlp'),
      ffmpegDir: tmp.path,
    );
    final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
    final template = p.join(outDir.path, 'live.%(ext)s');
    for (final name in [
      'live.mp4',
      'live.mp4.part',
      'live.f137.mp4.part',
      'live.mkv',
      'live-notes.txt',
      'live2.mp4',
      'other.mp4',
    ]) {
      File(p.join(outDir.path, name)).writeAsStringSync('x');
    }
    downloader.deleteOutput(template);
    expect(File(p.join(outDir.path, 'live.mp4')).existsSync(), isFalse);
    expect(
      File(p.join(outDir.path, 'live.mp4.part')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(outDir.path, 'live.f137.mp4.part')).existsSync(),
      isFalse,
    );
    expect(File(p.join(outDir.path, 'live.mkv')).existsSync(), isFalse);
    expect(
      File(p.join(outDir.path, 'live-notes.txt')).existsSync(),
      isTrue,
    );
    expect(File(p.join(outDir.path, 'live2.mp4')).existsSync(), isTrue);
    expect(File(p.join(outDir.path, 'other.mp4')).existsSync(), isTrue);
  });

  test('deletePartial deletes only this download\'s partial files', () {
    final downloader = YtDlpDownloader(
      ytDlpPath: p.join(tmp.path, 'no-such-yt-dlp'),
      ffmpegDir: tmp.path,
    );
    final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
    final template = p.join(outDir.path, 'live.%(ext)s');
    for (final name in [
      'live.mp4',
      'live.mp4.part',
      'live.f140.m4a.part',
      'live-notes.txt.part',
      'live2.mp4.part',
    ]) {
      File(p.join(outDir.path, name)).writeAsStringSync('x');
    }
    downloader.deletePartial(template);
    expect(File(p.join(outDir.path, 'live.mp4')).existsSync(), isTrue);
    expect(
      File(p.join(outDir.path, 'live.mp4.part')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(outDir.path, 'live.f140.m4a.part')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(outDir.path, 'live-notes.txt.part')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(outDir.path, 'live2.mp4.part')).existsSync(),
      isTrue,
    );
  });

  test(
      'the output fallback does not mistake an unrelated file for the download',
      () async {
    final fake = await makeFake('yt-dlp', _unrelatedOnlyScript);
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
    expect(events.length, 1);
    final failed = events.single as DownloadFailed;
    expect(failed.code, 'yt-dlp-no-output');
  });

  group('probe', () {
    late _FakeProcess fake;
    late List<List<String>> calls;
    late YtDlpDownloader downloader;

    // Builds a canned `yt-dlp -J` JSON payload.
    String probeJson() => jsonEncode({
      'title': 'Test video',
      'thumbnail': 'https://example.com/thumb.jpg',
      'duration': 125,
      'formats': [
        {
          'format_id': '137',
          'ext': 'mp4',
          'resolution': '1920x1080',
          'width': 1920,
          'height': 1080,
          'filesize': 12345678,
          'filesize_approx': null,
          'vcodec': 'avc1.640028',
          'acodec': 'none',
          'fps': 30,
          'format_note': '1080p',
        },
        {
          'format_id': '140',
          'ext': 'm4a',
          'resolution': 'audio only',
          'width': null,
          'height': null,
          'filesize': 123456,
          'filesize_approx': null,
          'vcodec': 'none',
          'acodec': 'mp4a.40.2',
          'fps': null,
          'format_note': 'medium',
        },
      ],
    });

    setUp(() {
      fake = _FakeProcess();
      calls = <List<String>>[];
      downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          return fake;
        },
      );
    });

    test('probe returns metadata and formats for a supported URL',
        () async {
      fake.addStdout(probeJson());
      fake.closeStreams();
      fake.completeExit(0);
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
      );
      expect(result.supported, isTrue);
      expect(result.title, 'Test video');
      expect(result.thumbnail, 'https://example.com/thumb.jpg');
      expect(result.durationSeconds, 125);
      expect(result.formats.length, 2);
      final video = result.formats.first;
      expect(video.formatId, '137');
      expect(video.ext, 'mp4');
      expect(video.resolution, '1920x1080');
      expect(video.width, 1920);
      expect(video.height, 1080);
      expect(video.filesize, 12345678);
      expect(video.vcodec, 'avc1.640028');
      expect(video.acodec, 'none');
      expect(video.fps, 30.0);
      expect(video.note, '1080p');
      final audio = result.formats.last;
      expect(audio.formatId, '140');
      expect(audio.vcodec, 'none');
      expect(audio.acodec, 'mp4a.40.2');
      final args = calls.single;
      expect(args, contains('-J'));
      expect(args, contains('--no-playlist'));
      expect(args.last, 'https://www.youtube.com/watch?v=xyz');
    });

    test('probe maps an unsupported URL to supported false', () async {
      fake.addStderr('ERROR: Unsupported URL: https://example.com/page');
      fake.closeStreams();
      fake.completeExit(1);
      final result = await downloader.probe(url: 'https://example.com/page');
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-unsupported');
      expect(result.errorMessage, contains('Unsupported URL'));
    });

    test('probe maps a private video to unavailable', () async {
      fake.addStderr(
        'ERROR: [youtube] abc123: Private video. Sign in if you have been granted access to this video',
      );
      fake.closeStreams();
      fake.completeExit(1);
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=abc123',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'unavailable');
    });

    test('probe maps other failures to yt-dlp-probe-failed', () async {
      fake.addStderr('WARNING: some warning');
      fake.addStderr('ERROR: unable to download video data');
      fake.closeStreams();
      fake.completeExit(1);
      final result = await downloader.probe(
        url: 'https://example.com/video',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-probe-failed');
      expect(result.errorMessage, contains('unable to download video data'));
    });

    test('probe times out and kills the process', () async {
      // The fake never exits on its own; kill() completes exitCode.
      final result = await downloader.probe(
        url: 'https://example.com/video',
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-timeout');
      expect(fake.killed, isTrue);
    });

    test('probe without cookies passes no --cookies flag', () async {
      fake.addStdout(probeJson());
      fake.closeStreams();
      fake.completeExit(0);
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
      );
      expect(result.supported, isTrue);
      expect(calls.single, isNot(contains('--cookies')));
      expect(calls.single, isNot(contains('--referer')));
    });

    test('probe writes cookies to a temp Netscape file and deletes it',
        () async {
      String? cookiePath;
      String? cookieContent;
      downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          final index = args.indexOf('--cookies');
          if (index != -1) {
            cookiePath = args[index + 1];
            cookieContent = File(cookiePath!).readAsStringSync();
          }
          fake.addStdout(probeJson());
          fake.closeStreams();
          fake.completeExit(0);
          return fake;
        },
      );
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
        cookie: 'session=abc123; theme=dark',
        referrer: 'https://www.youtube.com/watch?v=xyz',
      );
      expect(result.supported, isTrue);
      expect(cookiePath, isNotNull);
      expect(
        cookieContent,
        '# Netscape HTTP Cookie File\n'
        '.www.youtube.com\tTRUE\t/\tTRUE\t0\tsession\tabc123\n'
        '.www.youtube.com\tTRUE\t/\tTRUE\t0\ttheme\tdark\n',
      );
      expect(File(cookiePath!).existsSync(), isFalse);
      expect(Directory(p.dirname(cookiePath!)).existsSync(), isFalse);
      final args = calls.single;
      expect(args, contains('--cookies'));
      expect(args, contains('--referer'));
      expect(args, contains('https://www.youtube.com/watch?v=xyz'));
    });

    test('probe scrubs the cookies path from error messages', () async {
      String? cookiePath;
      downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          // A fresh process per spawn: the retry runs a second
          // process, and a fake's streams can only be listened to once.
          calls.add(args);
          final attempt = _FakeProcess();
          final index = args.indexOf('--cookies');
          if (index != -1) {
            cookiePath = args[index + 1];
          }
          attempt.addStderr('ERROR: could not read $cookiePath');
          attempt.closeStreams();
          attempt.completeExit(1);
          return attempt;
        },
      );
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
        cookie: 'session=abc123',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-probe-failed');
      expect(result.errorMessage, isNot(contains(cookiePath!)));
      expect(result.errorMessage, contains('<cookies-file>'));
      expect(calls.length, 2);
    });

    test('probe retries without cookies when the cookie run fails with a format error',
        () async {
      final first = _FakeProcess();
      final second = _FakeProcess();
      downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          if (calls.length == 1) {
            first.addStderr(
              'ERROR: [youtube] xyz: Requested format is not available. '
              'Use --list-formats for a list of available formats',
            );
            first.closeStreams();
            first.completeExit(1);
            return first;
          }
          second.addStdout(probeJson());
          second.closeStreams();
          second.completeExit(0);
          return second;
        },
      );
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
        cookie: 'session=abc123',
        referrer: 'https://www.youtube.com/watch?v=xyz',
      );
      expect(result.supported, isTrue);
      expect(result.title, 'Test video');
      expect(calls.length, 2);
      expect(calls.first, contains('--cookies'));
      expect(calls.last, isNot(contains('--cookies')));
      expect(calls.last, contains('--referer'));
    });

    test('probe reports the first error when the retry also fails',
        () async {
      final first = _FakeProcess();
      final second = _FakeProcess();
      downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          if (calls.length == 1) {
            first.addStderr(
              'ERROR: [youtube] xyz: Requested format is not available. '
              'Use --list-formats for a list of available formats',
            );
            first.closeStreams();
            first.completeExit(1);
            return first;
          }
          second.addStderr('ERROR: unable to download video data');
          second.closeStreams();
          second.completeExit(1);
          return second;
        },
      );
      final result = await downloader.probe(
        url: 'https://www.youtube.com/watch?v=xyz',
        cookie: 'session=abc123',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-probe-failed');
      expect(
        result.errorMessage,
        contains('Requested format is not available'),
      );
      expect(calls.length, 2);
    });

    test('probe does not retry an unsupported URL', () async {
      fake.addStderr('ERROR: Unsupported URL: https://example.com/page');
      fake.closeStreams();
      fake.completeExit(1);
      final result = await downloader.probe(
        url: 'https://example.com/page',
        cookie: 'session=abc123',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-unsupported');
      expect(calls.length, 1);
    });

    test('probe does not retry when no cookie was given', () async {
      fake.addStderr('ERROR: unable to download video data');
      fake.closeStreams();
      fake.completeExit(1);
      final result = await downloader.probe(
        url: 'https://example.com/video',
      );
      expect(result.supported, isFalse);
      expect(result.errorCode, 'yt-dlp-probe-failed');
      expect(calls.length, 1);
    });
  });

  group('start with format and cookies', () {
    test('start passes -f, --cookies and --referer to yt-dlp', () async {
      final fake = _FakeProcess();
      final calls = <List<String>>[];
      final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
      final finalPath = p.join(outDir.path, 'live.mp4');
      File(finalPath).writeAsStringSync('x');
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          fake.addStdout(
            '[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30',
          );
          fake.addStdout(finalPath);
          fake.closeStreams();
          fake.completeExit(0);
          return fake;
        },
      );
      final events = await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
            format: '137+140',
            cookie: 'session=abc123',
            referrer: 'https://www.youtube.com/watch?v=xyz',
          )
          .toList();
      expect(events.last, isA<DownloadCompleted>());
      final args = calls.single;
      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], '137+140');
      expect(args, contains('--cookies'));
      expect(args, contains('--referer'));
      expect(args.last, 'https://www.youtube.com/watch?v=xyz');
    });

    test('start deletes the cookie file when the download completes',
        () async {
      final fake = _FakeProcess();
      String? cookiePath;
      final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
      final finalPath = p.join(outDir.path, 'live.mp4');
      File(finalPath).writeAsStringSync('x');
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          final index = args.indexOf('--cookies');
          if (index != -1) cookiePath = args[index + 1];
          fake.addStdout(finalPath);
          fake.closeStreams();
          fake.completeExit(0);
          return fake;
        },
      );
      await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
            cookie: 'session=abc123',
          )
          .toList();
      expect(cookiePath, isNotNull);
      expect(File(cookiePath!).existsSync(), isFalse);
      expect(Directory(p.dirname(cookiePath!)).existsSync(), isFalse);
    });

    test('start deletes the cookie file when the download is paused',
        () async {
      final fake = _FakeProcess();
      String? cookiePath;
      final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          final index = args.indexOf('--cookies');
          if (index != -1) cookiePath = args[index + 1];
          fake.addStdout(
            '[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30',
          );
          return fake;
        },
      );
      final events = <DownloadEvent>[];
      final done = Completer<void>();
      downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
            cookie: 'session=abc123',
          )
          .listen(events.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await downloader.pause('dl-1');
      await done.future.timeout(const Duration(seconds: 10));
      final last = events.last;
      expect(last, isA<DownloadStateChanged>());
      expect((last as DownloadStateChanged).status, DownloadStatus.paused);
      expect(cookiePath, isNotNull);
      expect(File(cookiePath!).existsSync(), isFalse);
      expect(Directory(p.dirname(cookiePath!)).existsSync(), isFalse);
    });

    test('start retries without cookies when the cookie run fails with a format error',
        () async {
      final first = _FakeProcess();
      final second = _FakeProcess();
      final calls = <List<String>>[];
      String? cookiePath;
      final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
      final finalPath = p.join(outDir.path, 'live.mp4');
      File(finalPath).writeAsStringSync('x');
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          final index = args.indexOf('--cookies');
          if (index != -1) cookiePath = args[index + 1];
          if (calls.length == 1) {
            first.addStderr(
              'ERROR: [youtube] xyz: Requested format is not available. '
              'Use --list-formats for a list of available formats',
            );
            first.closeStreams();
            first.completeExit(1);
            return first;
          }
          second.addStdout(
            '[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30',
          );
          second.addStdout(finalPath);
          second.closeStreams();
          second.completeExit(0);
          return second;
        },
      );
      final events = await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(outDir.path, 'live.%(ext)s'),
            format: '137+bestaudio',
            cookie: 'session=abc123',
            referrer: 'https://www.youtube.com/watch?v=xyz',
          )
          .toList();
      expect(events.last, isA<DownloadCompleted>());
      expect(calls.length, 2);
      expect(calls.first, contains('--cookies'));
      expect(calls.last, isNot(contains('--cookies')));
      expect(calls.last, contains('-f'));
      expect(calls.last[calls.last.indexOf('-f') + 1], '137+bestaudio');
      expect(calls.last, contains('--referer'));
      expect(cookiePath, isNotNull);
      expect(File(cookiePath!).existsSync(), isFalse);
    });

    test('start reports the first error when the retry also fails',
        () async {
      final first = _FakeProcess();
      final second = _FakeProcess();
      final calls = <List<String>>[];
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          if (calls.length == 1) {
            first.addStderr(
              'ERROR: [youtube] xyz: Requested format is not available. '
              'Use --list-formats for a list of available formats',
            );
            first.closeStreams();
            first.completeExit(1);
            return first;
          }
          second.addStderr('ERROR: unable to download video data');
          second.closeStreams();
          second.completeExit(1);
          return second;
        },
      );
      final events = await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
            format: '137+bestaudio',
            cookie: 'session=abc123',
          )
          .toList();
      expect(events.length, 1);
      final failed = events.single as DownloadFailed;
      expect(failed.code, 'yt-dlp-failed');
      expect(
        failed.message,
        contains('Requested format is not available'),
      );
      expect(calls.length, 2);
    });

    test('start does not retry a non-format failure', () async {
      final fake = _FakeProcess();
      final calls = <List<String>>[];
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          fake.addStderr('ERROR: unable to download video data');
          fake.closeStreams();
          fake.completeExit(1);
          return fake;
        },
      );
      final events = await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
            cookie: 'session=abc123',
          )
          .toList();
      expect(events.length, 1);
      final failed = events.single as DownloadFailed;
      expect(failed.message, contains('unable to download video data'));
      expect(calls.length, 1);
    });

    test('start does not retry when no cookie was given', () async {
      final fake = _FakeProcess();
      final calls = <List<String>>[];
      final downloader = YtDlpDownloader(
        ytDlpPath: 'yt-dlp',
        ffmpegDir: tmp.path,
        processStarter: (String exe, List<String> args) async {
          calls.add(args);
          fake.addStderr(
            'ERROR: [youtube] xyz: Requested format is not available. '
            'Use --list-formats for a list of available formats',
          );
          fake.closeStreams();
          fake.completeExit(1);
          return fake;
        },
      );
      final events = await downloader
          .start(
            downloadId: 'dl-1',
            url: 'https://www.youtube.com/watch?v=xyz',
            outputTemplate: p.join(tmp.path, 'live.%(ext)s'),
            format: '137+bestaudio',
          )
          .toList();
      expect(events.length, 1);
      final failed = events.single as DownloadFailed;
      expect(
        failed.message,
        contains('Requested format is not available'),
      );
      expect(calls.length, 1);
    });
  });

  test('buildNetscapeCookies starts with the Netscape header line', () {
    final content = buildNetscapeCookies(
      cookieHeader: 'session=abc123',
      url: Uri.parse('https://www.youtube.com/watch?v=xyz'),
    );
    expect(content.startsWith('# Netscape HTTP Cookie File\n'), isTrue);
  });

  test('buildNetscapeCookies writes one line per cookie', () {
    final content = buildNetscapeCookies(
      cookieHeader: 'session=abc123; theme=dark',
      url: Uri.parse('https://www.youtube.com/watch?v=xyz'),
    );
    expect(
      content,
      '# Netscape HTTP Cookie File\n'
      '.www.youtube.com\tTRUE\t/\tTRUE\t0\tsession\tabc123\n'
      '.www.youtube.com\tTRUE\t/\tTRUE\t0\ttheme\tdark\n',
    );
  });

  test('buildNetscapeCookies marks http cookies as not secure', () {
    final content = buildNetscapeCookies(
      cookieHeader: 'a=b',
      url: Uri.parse('http://example.com/video'),
    );
    expect(content, '# Netscape HTTP Cookie File\n' '.example.com\tTRUE\t/\tFALSE\t0\ta\tb\n');
  });

  test('buildNetscapeCookies keeps equals signs in values', () {
    final content = buildNetscapeCookies(
      cookieHeader: 'token=abc=def',
      url: Uri.parse('https://example.com/'),
    );
    expect(content, '# Netscape HTTP Cookie File\n' '.example.com\tTRUE\t/\tTRUE\t0\ttoken\tabc=def\n');
  });

  test('scrubCookieMaterial replaces the cookies path and redacts Cookie headers',
      () {
    expect(
      scrubCookieMaterial(
        'ERROR: could not read /tmp/pdm-cookies-abc/cookies.txt',
        '/tmp/pdm-cookies-abc/cookies.txt',
      ),
      'ERROR: could not read <cookies-file>',
    );
    expect(
      scrubCookieMaterial('request headers: Cookie: session=abc123', null),
      'request headers: Cookie: <redacted>',
    );
    expect(
      scrubCookieMaterial('ERROR: something else', null),
      'ERROR: something else',
    );
  });
}
