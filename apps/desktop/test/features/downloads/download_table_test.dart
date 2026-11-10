import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/download_table.dart';
import 'package:pdm/shared/theme/app_theme.dart';

Download _download({
  DownloadState state = DownloadState.completed,
  int downloadedBytes = 0,
  int totalBytes = 1000,
  int bytesPerSecond = 0,
  DateTime? createdAt,
}) {
  return Download(
    id: 'dl-1',
    url: 'https://example.com/f.pdf',
    fileName: 'f.pdf',
    state: state,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    bytesPerSecond: bytesPerSecond,
    createdAt: createdAt,
  );
}

void main() {
  group('formatAdded', () {
    test('today shows "Today h:mm AM/PM"', () {
      final now = DateTime(2026, 11, 10, 22, 29);
      expect(
        formatAdded(DateTime(2026, 11, 10, 22, 29), now: now),
        'Today 10:29 PM',
      );
      expect(
        formatAdded(DateTime(2026, 11, 10, 9, 5), now: now),
        'Today 9:05 AM',
      );
    });

    test('yesterday shows "Yesterday h:mm AM/PM"', () {
      final now = DateTime(2026, 11, 10, 22, 29);
      expect(
        formatAdded(DateTime(2026, 11, 9, 8, 0), now: now),
        'Yesterday 8:00 AM',
      );
    });

    test('older dates show "Mon d, yyyy h:mm AM/PM"', () {
      final now = DateTime(2026, 11, 10, 22, 29);
      expect(
        formatAdded(DateTime(2026, 11, 5, 14, 3), now: now),
        'Nov 5, 2026 2:03 PM',
      );
    });

    test('null shows an empty string', () {
      expect(formatAdded(null), '');
    });
  });

  group('downloadStatusText', () {
    test('completed shows just the state', () {
      expect(downloadStatusText(_download()), 'Completed');
    });

    test('downloading with a known total shows the percent', () {
      final d = _download(
        state: DownloadState.downloading,
        downloadedBytes: 250,
        totalBytes: 1000,
      );
      expect(downloadStatusText(d), 'Downloading 25%');
    });

    test('downloading with an unknown total shows no percent', () {
      final d = _download(
        state: DownloadState.downloading,
        downloadedBytes: 250,
        totalBytes: -1,
      );
      expect(downloadStatusText(d), 'Downloading');
    });

    test('paused shows the percent', () {
      final d = _download(
        state: DownloadState.paused,
        downloadedBytes: 500,
        totalBytes: 1000,
      );
      expect(downloadStatusText(d), 'Paused 50%');
    });
  });

  group('downloadSizeText', () {
    test('a known total shows the total', () {
      expect(downloadSizeText(_download(totalBytes: 20500)), '20.0 KiB');
    });

    test('an unknown total shows the downloaded size, not -1 B', () {
      final d = _download(downloadedBytes: 159744, totalBytes: -1);
      expect(downloadSizeText(d), '156.0 KiB');
    });
  });

  group('downloadStatusColor', () {
    test('each state has its FDM color', () {
      final scheme = AppTheme.dark.colorScheme;
      expect(
        downloadStatusColor(scheme, DownloadState.completed),
        scheme.primary,
      );
      expect(
        downloadStatusColor(scheme, DownloadState.downloading),
        scheme.secondary,
      );
      expect(
        downloadStatusColor(scheme, DownloadState.paused),
        const Color(0xFFFACC15),
      );
      expect(
        downloadStatusColor(scheme, DownloadState.failed),
        scheme.error,
      );
      expect(
        downloadStatusColor(scheme, DownloadState.queued),
        scheme.onSurfaceVariant,
      );
      expect(
        downloadStatusColor(scheme, DownloadState.cancelled),
        scheme.onSurfaceVariant,
      );
    });
  });
}
