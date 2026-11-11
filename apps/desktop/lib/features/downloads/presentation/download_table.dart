import 'package:flutter/material.dart';

import '../domain/entities/download.dart';

/// Column widths for the FDM download table (`#`, Name, Size, Status,
/// row menu, Download, Upload, Added). Name is flexible and takes the
/// rest; the others are fixed so the header and the rows line up.
class DownloadTableColumns {
  static const double check = 40;
  static const double size = 90;
  static const double status = 120;
  static const double menu = 48;
  static const double speed = 90;
  static const double added = 150;
}

/// The amber used for a paused download (FDM shows paused in yellow).
const Color kPausedColor = Color(0xFFFACC15);

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GiB';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats the "Added" column like FDM: "Today 10:29 PM",
/// "Yesterday 8:00 AM", or "Nov 5, 2026 2:03 PM" for older dates.
/// A null timestamp shows as an empty string.
String formatAdded(DateTime? added, {DateTime? now}) {
  if (added == null) return '';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(added.year, added.month, added.day);
  final time = _formatTimeOfDay(added);
  if (day == today) return 'Today $time';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday $time';
  }
  return '${_months[added.month - 1]} ${added.day}, ${added.year} $time';
}

String _formatTimeOfDay(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final period = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:${t.minute.toString().padLeft(2, '0')} $period';
}

/// The text for the Status column: the state name, plus the percent
/// while an active download has a known total ("Downloading 25%").
String downloadStatusText(Download download) {
  final name = _capitalize(download.state.name);
  if ((download.state == DownloadState.downloading ||
          download.state == DownloadState.paused) &&
      download.totalBytes > 0) {
    final percent = (download.progress * 100).round();
    return '$name $percent%';
  }
  return name;
}

/// The text for the Size column: the total when the server sent one,
/// else the downloaded size so far (never "-1 B").
String downloadSizeText(Download download) {
  final bytes = download.totalBytes > 0
      ? download.totalBytes
      : download.downloadedBytes;
  return formatBytes(bytes);
}

/// The icon shown before the file name, by state. The file/folder
/// icon only appears for a finished or failed download; while a
/// download is running or paused it shows a state icon instead (a down
/// arrow while downloading, a play arrow while paused, as in FDM).
IconData downloadStateIcon(DownloadState state) {
  return switch (state) {
    DownloadState.downloading => Icons.arrow_downward,
    DownloadState.paused => Icons.play_arrow,
    DownloadState.completed => Icons.folder,
    DownloadState.failed ||
    DownloadState.queued ||
    DownloadState.cancelled => Icons.insert_drive_file,
  };
}

/// The color for the Status column, from the FDM palette.
Color downloadStatusColor(ColorScheme scheme, DownloadState state) {
  return switch (state) {
    DownloadState.completed => scheme.primary,
    DownloadState.downloading => scheme.secondary,
    DownloadState.paused => kPausedColor,
    DownloadState.failed => scheme.error,
    DownloadState.queued => scheme.onSurfaceVariant,
    DownloadState.cancelled => scheme.onSurfaceVariant,
  };
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
