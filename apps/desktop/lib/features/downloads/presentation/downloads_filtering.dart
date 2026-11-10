import 'package:pdm/features/downloads/domain/entities/download.dart';

enum DownloadSort { newest, oldest, name, size }

enum DownloadFilter {
  all,
  downloading,
  queued,
  paused,
  completed,
  failed,
  cancelled,
}

/// The downloads to show, after filter + search + sort.
///
/// The engine lists downloads oldest-first (`ORDER BY created_at ASC`),
/// so `newest` reverses that order and `oldest` keeps it. `size` is
/// largest first; a download with an unknown total (`totalBytes == -1`)
/// sorts last.
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
    case DownloadSort.name:
      visible.sort(
        (a, b) => a.fileName.toLowerCase().compareTo(
          b.fileName.toLowerCase(),
        ),
      );
    case DownloadSort.size:
      visible.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
  }
  return visible;
}

bool _matchesFilter(Download d, DownloadFilter filter) {
  switch (filter) {
    case DownloadFilter.all:
      return true;
    case DownloadFilter.downloading:
      return d.state == DownloadState.downloading;
    case DownloadFilter.queued:
      return d.state == DownloadState.queued;
    case DownloadFilter.paused:
      return d.state == DownloadState.paused;
    case DownloadFilter.completed:
      return d.state == DownloadState.completed;
    case DownloadFilter.failed:
      return d.state == DownloadState.failed;
    case DownloadFilter.cancelled:
      return d.state == DownloadState.cancelled;
  }
}
