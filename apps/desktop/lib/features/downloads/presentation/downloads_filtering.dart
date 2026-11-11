import 'dart:io';

import 'package:pdm/features/downloads/domain/entities/download.dart';

/// Sort orders, matching Free Download Manager's sort menu.
enum DownloadSort {
  newest,
  oldest,
  nameAsc,
  nameDesc,
  sizeDesc,
  sizeAsc,
  statusAsc,
  statusDesc,
}

/// Filters, matching Free Download Manager's filter menu.
enum DownloadFilter {
  all,
  missing,
  active,
  completed,
  torrent,
  video,
  music,
}

/// File extensions counted as video / music for the type filters.
/// Compared case-insensitively against the file name's extension.
const _videoExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'flv',
  'webm',
  'm4v',
  'mpg',
  'mpeg',
  '3gp',
  'ts',
  'm2ts',
  'vob',
  'ogv',
};

const _musicExtensions = {
  'mp3',
  'flac',
  'wav',
  'ogg',
  'm4a',
  'aac',
  'wma',
  'opus',
  'aiff',
  'alac',
};

/// The downloads to show, after filter + search + sort.
///
/// The engine lists downloads oldest-first (`ORDER BY created_at ASC`),
/// so `newest` reverses that order and `oldest` keeps it.
List<Download> visibleDownloads(
  List<Download> items, {
  required DownloadSort sort,
  required DownloadFilter filter,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  var visible = items.where((d) {
    if (!_matchesFilter(d, filter)) return false;
    if (q.isEmpty) return true;
    return d.fileName.toLowerCase().contains(q) ||
        d.url.toLowerCase().contains(q);
  }).toList();

  switch (sort) {
    case DownloadSort.newest:
      visible = visible.reversed.toList();
    case DownloadSort.oldest:
      break;
    case DownloadSort.nameAsc:
      visible.sort(
        (a, b) => a.fileName.toLowerCase().compareTo(
          b.fileName.toLowerCase(),
        ),
      );
    case DownloadSort.nameDesc:
      visible.sort(
        (a, b) => b.fileName.toLowerCase().compareTo(
          a.fileName.toLowerCase(),
        ),
      );
    case DownloadSort.sizeDesc:
      visible.sort(
        (a, b) => _compareSize(a.totalBytes, b.totalBytes, descending: true),
      );
    case DownloadSort.sizeAsc:
      visible.sort(
        (a, b) => _compareSize(a.totalBytes, b.totalBytes, descending: false),
      );
    case DownloadSort.statusAsc:
      visible.sort((a, b) => a.state.index.compareTo(b.state.index));
    case DownloadSort.statusDesc:
      visible.sort((a, b) => b.state.index.compareTo(a.state.index));
  }
  return visible;
}

/// Compares two totals. An unknown total (`totalBytes == -1`) sorts
/// last in both directions.
int _compareSize(int a, int b, {required bool descending}) {
  if (a < 0 && b < 0) return 0;
  if (a < 0) return 1;
  if (b < 0) return -1;
  return descending ? b.compareTo(a) : a.compareTo(b);
}

bool _matchesFilter(Download d, DownloadFilter filter) {
  switch (filter) {
    case DownloadFilter.all:
      return true;
    case DownloadFilter.missing:
      return _isMissing(d);
    case DownloadFilter.active:
      return d.state == DownloadState.queued ||
          d.state == DownloadState.downloading ||
          d.state == DownloadState.paused;
    case DownloadFilter.completed:
      return d.state == DownloadState.completed;
    case DownloadFilter.torrent:
      return _extension(d.fileName) == 'torrent';
    case DownloadFilter.video:
      return _videoExtensions.contains(_extension(d.fileName));
    case DownloadFilter.music:
      return _musicExtensions.contains(_extension(d.fileName));
  }
}

/// Whether a completed download's file is missing from disk. An
/// incomplete download is never missing (its file is a partial that
/// may legitimately not exist yet), and a download with no known path
/// cannot be judged.
bool _isMissing(Download d) {
  final path = d.filePath;
  if (path == null) return false;
  if (d.state != DownloadState.completed) return false;
  return !File(path).existsSync();
}

String _extension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}
