import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

void main() {
  group('parseYtDlpProgress (classic [download] lines)', () {
    test('parses a standard progress line', () {
      final p = parseYtDlpProgress(
        '[download]  45.2% of  123.45MiB at  1.23MiB/s ETA 00:30',
      );
      expect(p, isNotNull);
      expect(p!.percent, 45.2);
      expect(p.totalBytes, (123.45 * 1024 * 1024).round());
      expect(p.bytesPerSecond, (1.23 * 1024 * 1024).round());
      expect(
        p.downloadedBytes,
        (123.45 * 1024 * 1024 * 45.2 / 100).round(),
      );
    });

    test('parses KiB and GiB units', () {
      final kib = parseYtDlpProgress(
        '[download]  10.0% of  512.00KiB at  64.00KiB/s ETA 00:07',
      );
      expect(kib!.totalBytes, (512 * 1024).round());
      expect(kib.bytesPerSecond, (64 * 1024).round());
      final gib = parseYtDlpProgress(
        '[download]  99.9% of  2.50GiB at  10.00MiB/s ETA 00:01',
      );
      expect(gib!.totalBytes, (2.5 * 1024 * 1024 * 1024).round());
    });

    test('parses an unknown total', () {
      final p = parseYtDlpProgress(
        '[download]  12.0% of Unknown at  512.00KiB/s ETA 01:00',
      );
      expect(p, isNotNull);
      expect(p!.totalBytes, -1);
      expect(p.downloadedBytes, -1);
      expect(p.bytesPerSecond, (512 * 1024).round());
    });

    test('parses the 100% line without a speed', () {
      final p = parseYtDlpProgress('[download] 100% of  123.45MiB in 00:01');
      expect(p, isNotNull);
      expect(p!.percent, 100);
      expect(p.totalBytes, (123.45 * 1024 * 1024).round());
      expect(p.bytesPerSecond, 0);
      expect(p.downloadedBytes, p.totalBytes);
    });

    test('parses an estimated total with a tilde', () {
      final p = parseYtDlpProgress(
        '[download]  30.0% of ~ 50.00MiB at  2.00MiB/s ETA 00:17',
      );
      expect(p, isNotNull);
      expect(p!.totalBytes, (50 * 1024 * 1024).round());
    });

    test('returns null for non-progress lines', () {
      expect(
        parseYtDlpProgress('[download] Destination: /tmp/live.m3u8.mp4'),
        isNull,
      );
      expect(
        parseYtDlpProgress('[Merger] Merging formats into "/tmp/live.mp4"'),
        isNull,
      );
      expect(parseYtDlpProgress('[youtube] Extracting URL'), isNull);
      expect(parseYtDlpProgress(''), isNull);
      expect(parseYtDlpProgress('garbage'), isNull);
    });
  });

  group('parseYtDlpStreamProgress (--progress-template lines)', () {
    test('parses a downloading line with every field', () {
      final u = parseYtDlpStreamProgress(
        'PDMPROGRESS|downloading|137|1048576|5242880|NA|2097152',
      );
      expect(u, isNotNull);
      expect(u!.formatId, '137');
      expect(u.finished, isFalse);
      expect(u.downloadedBytes, 1048576);
      expect(u.totalBytes, 5242880);
      expect(u.bytesPerSecond, 2097152);
    });

    test('parses a finished line', () {
      final u = parseYtDlpStreamProgress(
        'PDMPROGRESS|finished|140|1000000|1000000|NA|NA',
      );
      expect(u!.finished, isTrue);
      expect(u.formatId, '140');
      expect(u.bytesPerSecond, 0);
    });

    test('falls back to the estimated total when the exact one is unknown',
        () {
      final u = parseYtDlpStreamProgress(
        'PDMPROGRESS|downloading|0|1024|NA|1084384.0|0',
      );
      expect(u!.totalBytes, 1084384);
    });

    test('ignores lines without the prefix or with the wrong arity', () {
      expect(parseYtDlpStreamProgress('[download]  10.0% of 1MiB'), isNull);
      expect(parseYtDlpStreamProgress('PDMPROGRESS|downloading|137'), isNull);
      expect(parseYtDlpStreamProgress(''), isNull);
    });
  });

  group('parseYtDlpStreamPlan (--print before_dl line)', () {
    test('parses the requested formats of a two-stream download', () {
      final plan = parseYtDlpStreamPlan(
        'PDMPLAN|["137", "140"]|[5000000, 1000000]|[]|137+140|NA|6000000',
      );
      expect(plan, isNotNull);
      expect(plan!.formatIds, ['137', '140']);
      expect(plan.sizes, [5000000, 1000000]);
      expect(plan.totalBytes, 6000000);
    });

    test('parses a single-format download from the format_id fields', () {
      final plan = parseYtDlpStreamPlan('PDMPLAN|[]|[]|[]|137|5000000|NA');
      expect(plan!.formatIds, ['137']);
      expect(plan.sizes, [5000000]);
      expect(plan.totalBytes, 5000000);
    });

    test('keeps unknown sizes as null', () {
      final plan = parseYtDlpStreamPlan(
        'PDMPLAN|["137", "140"]|[]|[]|137+140|NA|NA',
      );
      expect(plan!.formatIds, ['137', '140']);
      expect(plan.sizes, [null, null]);
      expect(plan.totalBytes, isNull);
    });

    test('ignores lines without the prefix', () {
      expect(parseYtDlpStreamPlan('PDMPROGRESS|downloading|137|1|2|NA|0'),
          isNull);
      expect(parseYtDlpStreamPlan('garbage'), isNull);
    });
  });

  group('YtDlpProgressTracker', () {
    YtDlpStreamPlan twoStreams() => parseYtDlpStreamPlan(
          'PDMPLAN|["137", "140"]|[5000000, 1000000]|[]|137+140|NA|6000000',
        )!;

    YtDlpStreamUpdate update(
      String id, {
      required int downloaded,
      required int total,
      bool finished = false,
      int speed = 0,
    }) =>
        YtDlpStreamUpdate(
          formatId: id,
          finished: finished,
          downloadedBytes: downloaded,
          totalBytes: total,
          bytesPerSecond: speed,
        );

    test('aggregates two streams into one monotonic run', () {
      final tracker = YtDlpProgressTracker(plan: twoStreams());
      final first = tracker.update(update('137', downloaded: 2500000, total: 5000000));
      final videoDone =
          tracker.update(update('137', downloaded: 5000000, total: 5000000, finished: true));
      final audioStart = tracker.update(update('140', downloaded: 100000, total: 1000000));

      expect(first.percent, closeTo(41.7, 0.1));
      expect(videoDone.percent, closeTo(83.3, 0.1));
      expect(audioStart.percent, greaterThanOrEqualTo(videoDone.percent));
      expect(audioStart.percent, lessThan(100));
    });

    test('never reaches 100% before the run completes', () {
      final tracker = YtDlpProgressTracker(plan: twoStreams());
      tracker.update(update('137', downloaded: 5000000, total: 5000000, finished: true));
      final last =
          tracker.update(update('140', downloaded: 1000000, total: 1000000, finished: true));
      expect(last.percent, 99);
    });

    test('without a plan, a finished stream is held below 100%', () {
      final tracker = YtDlpProgressTracker();
      final running = tracker.update(update('137', downloaded: 2500000, total: 5000000));
      final finished =
          tracker.update(update('137', downloaded: 5000000, total: 5000000, finished: true));
      expect(running.percent, closeTo(50, 0.1));
      expect(finished.percent, 99);
    });

    test('without a plan, a second stream turns the run total unknown', () {
      final tracker = YtDlpProgressTracker();
      tracker.update(update('137', downloaded: 2500000, total: 5000000));
      tracker.update(update('137', downloaded: 5000000, total: 5000000, finished: true));
      final second = tracker.update(update('140', downloaded: 500000, total: 1000000));
      // Keeping the first stream's bytes would need a total that
      // keeps growing: the reported percent would fall back instead.
      expect(second.percent, 0);
      expect(second.totalBytes, -1);
      expect(second.downloadedBytes, 5500000);
    });

    test('a single stream reports its own percent', () {
      final tracker = YtDlpProgressTracker(
        plan: parseYtDlpStreamPlan('PDMPLAN|[]|[]|[]|137|5000000|NA'),
      );
      final p = tracker.update(update('137', downloaded: 2500000, total: 5000000));
      expect(p.percent, closeTo(50, 0.1));
      expect(p.totalBytes, 5000000);
    });

    test('passes the speed through', () {
      final tracker = YtDlpProgressTracker(plan: twoStreams());
      final p = tracker.update(
        update('137', downloaded: 100, total: 5000000, speed: 2097152),
      );
      expect(p.bytesPerSecond, 2097152);
    });

    test('a plan arriving mid-run applies to the following updates', () {
      final tracker = YtDlpProgressTracker();
      tracker.update(update('137', downloaded: 1000000, total: 5000000));
      tracker.applyPlan(twoStreams());
      final p = tracker.update(update('137', downloaded: 2500000, total: 5000000));
      expect(p.totalBytes, 6000000);
      expect(p.percent, closeTo(41.7, 0.1));
    });

    test('a plan whose sizes disagree with the transfer uses real bytes', () {
      // yt-dlp's filesize metadata is the *estimated* size; a real
      // two-stream run transferred 2.7 MB + 0.32 MB while the plan said
      // 5 MB + 1 MB. Holding the plan total would leave the run stuck
      // near 50% after both streams finished.
      final tracker = YtDlpProgressTracker(plan: twoStreams());
      tracker.update(update('137', downloaded: 2701791, total: 2701791));
      tracker.update(
        update('137', downloaded: 2701791, total: 2701791, finished: true),
      );
      final audioDone = tracker.update(
        update('140', downloaded: 324238, total: 324238, finished: true),
      );
      expect(audioDone.totalBytes, 2701791 + 324238);
      expect(audioDone.downloadedBytes, 2701791 + 324238);
      expect(audioDone.percent, 99);
    });

    test('a real two-stream yt-dlp run reports one monotonic progress', () {
      // Captured from the bundled yt-dlp (2026.10.26) downloading a
      // `<video>+bestaudio` pick through this package's flags. Each
      // stream prints its own 0→100%; replaying the lines must yield a
      // run that only climbs (no restart when the second stream begins)
      // and ends at the bytes really transferred.
      final lines =
          File('test/fixtures/yt_dlp_two_stream.txt').readAsLinesSync();
      final tracker = YtDlpProgressTracker();
      final run = <YtDlpRunProgress>[];
      for (final line in lines) {
        final plan = parseYtDlpStreamPlan(line);
        if (plan != null) {
          tracker.applyPlan(plan);
          continue;
        }
        final stream = parseYtDlpStreamProgress(line);
        if (stream != null) run.add(tracker.update(stream));
      }
      expect(run, isNotEmpty);
      var lastPercent = 0.0;
      for (final p in run) {
        final percent = p.totalBytes > 0
            ? p.downloadedBytes * 100 / p.totalBytes
            : 0.0;
        expect(percent, greaterThanOrEqualTo(lastPercent - 0.01));
        lastPercent = percent;
      }
      // The video stream finishing is not the run finishing: the audio
      // stream is still ahead, and it is sized from the plan.
      final videoDone = run.firstWhere(
        (p) => p.downloadedBytes == 2701791,
      );
      expect(videoDone.totalBytes, 2701791 + 1000000);
      expect(videoDone.percent, lessThan(80));
      final last = run.last;
      expect(last.downloadedBytes, 2701791 + 324238);
      expect(last.totalBytes, 2701791 + 324238);
    });
  });
}
