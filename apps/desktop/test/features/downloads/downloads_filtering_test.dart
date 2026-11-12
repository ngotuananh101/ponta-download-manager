import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';

Download _d(
  String id, {
  String fileName = 'file',
  String url = 'https://example.com/file',
  DownloadState state = DownloadState.downloading,
  int totalBytes = 1000,
  int downloadedBytes = 0,
  String? filePath,
}) {
  return Download(
    id: id,
    url: url,
    fileName: fileName,
    state: state,
    totalBytes: totalBytes,
    downloadedBytes: downloadedBytes,
    filePath: filePath,
  );
}

void main() {
  group('visibleDownloads', () {
    // Creation order (oldest first, as the engine lists them).
    final items = [
      _d('dl-1', fileName: 'beta.zip', state: DownloadState.completed, totalBytes: 3000),
      _d('dl-2', fileName: 'alpha.zip', state: DownloadState.downloading, totalBytes: 1000),
      _d('dl-3', fileName: 'gamma.zip', state: DownloadState.failed, totalBytes: 2000),
      _d('dl-4', fileName: 'delta.zip', state: DownloadState.queued, totalBytes: -1),
    ];

    test('newest reverses creation order, oldest keeps it', () {
      final newest = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(newest.map((d) => d.id).toList(), ['dl-4', 'dl-3', 'dl-2', 'dl-1']);
      final oldest = visibleDownloads(
        items,
        sort: DownloadSort.oldest,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(oldest.map((d) => d.id).toList(), ['dl-1', 'dl-2', 'dl-3', 'dl-4']);
    });

    test('A-Z sorts by name ascending, Z-A descending', () {
      final asc = visibleDownloads(
        items,
        sort: DownloadSort.nameAsc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(
        asc.map((d) => d.fileName).toList(),
        ['alpha.zip', 'beta.zip', 'delta.zip', 'gamma.zip'],
      );
      final desc = visibleDownloads(
        items,
        sort: DownloadSort.nameDesc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(
        desc.map((d) => d.fileName).toList(),
        ['gamma.zip', 'delta.zip', 'beta.zip', 'alpha.zip'],
      );
    });

    test('By size: large sorts largest first, unknown total last', () {
      final sorted = visibleDownloads(
        items,
        sort: DownloadSort.sizeDesc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(sorted.map((d) => d.id).toList(), ['dl-1', 'dl-3', 'dl-2', 'dl-4']);
    });

    test('By size: small sorts smallest first, unknown total last', () {
      final sorted = visibleDownloads(
        items,
        sort: DownloadSort.sizeAsc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(sorted.map((d) => d.id).toList(), ['dl-2', 'dl-3', 'dl-1', 'dl-4']);
    });

    test('By status sorts by state order, ascending and descending', () {
      final asc = visibleDownloads(
        items,
        sort: DownloadSort.statusAsc,
        filter: DownloadFilter.all,
        query: '',
      );
      // queued < downloading < paused < completed < missing < failed < cancelled.
      expect(asc.map((d) => d.id).toList(), ['dl-4', 'dl-2', 'dl-1', 'dl-3']);
      final desc = visibleDownloads(
        items,
        sort: DownloadSort.statusDesc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(desc.map((d) => d.id).toList(), ['dl-3', 'dl-1', 'dl-2', 'dl-4']);
    });

    test('Active keeps queued, downloading and paused only', () {
      final active = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.active,
        query: '',
      );
      expect(active.map((d) => d.id).toList(), ['dl-4', 'dl-2']);
      final completed = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.completed,
        query: '',
      );
      expect(completed.map((d) => d.id).toList(), ['dl-1']);
    });

    test('type filters match the file extension, case-insensitively', () {
      final typed = [
        _d('dl-1', fileName: 'movie.MP4'),
        _d('dl-2', fileName: 'song.flac'),
        _d('dl-3', fileName: 'pack.torrent'),
        _d('dl-4', fileName: 'archive.zip'),
      ];
      final video = visibleDownloads(
        typed,
        sort: DownloadSort.newest,
        filter: DownloadFilter.video,
        query: '',
      );
      expect(video.map((d) => d.id).toList(), ['dl-1']);
      final music = visibleDownloads(
        typed,
        sort: DownloadSort.newest,
        filter: DownloadFilter.music,
        query: '',
      );
      expect(music.map((d) => d.id).toList(), ['dl-2']);
      final torrent = visibleDownloads(
        typed,
        sort: DownloadSort.newest,
        filter: DownloadFilter.torrent,
        query: '',
      );
      expect(torrent.map((d) => d.id).toList(), ['dl-3']);
    });

    test('Missing Files keeps missing rows only', () {
      final rows = [
        _d('dl-1', fileName: 'gone.bin', state: DownloadState.missing),
        _d('dl-2', fileName: 'present.bin', state: DownloadState.completed),
        _d('dl-3', fileName: 'active.bin', state: DownloadState.downloading),
      ];
      final result = visibleDownloads(
        rows,
        sort: DownloadSort.newest,
        filter: DownloadFilter.missing,
        query: '',
      );
      // Only the row already marked missing at load. The state, not a
      // live disk check, decides: a file deleted mid-session shows
      // Missing only after the next app start.
      expect(result.map((d) => d.id).toList(), ['dl-1']);
    });

    test('By status sorts missing between completed and failed', () {
      final rows = [
        _d('dl-1', fileName: 'a.zip', state: DownloadState.failed),
        _d('dl-2', fileName: 'b.zip', state: DownloadState.missing),
        _d('dl-3', fileName: 'c.zip', state: DownloadState.completed),
      ];
      final asc = visibleDownloads(
        rows,
        sort: DownloadSort.statusAsc,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(asc.map((d) => d.id).toList(), ['dl-3', 'dl-2', 'dl-1']);
    });

    test('search matches file name and URL, case-insensitively', () {
      final byName = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.all,
        query: 'ALPHA',
      );
      expect(byName.map((d) => d.id).toList(), ['dl-2']);
      final byUrl = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.all,
        query: 'example.com',
      );
      expect(byUrl.length, 4);
    });

    test('filter and search combine', () {
      final result = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.completed,
        query: 'beta',
      );
      expect(result.map((d) => d.id).toList(), ['dl-1']);
      final none = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.completed,
        query: 'alpha',
      );
      expect(none, isEmpty);
    });
  });
}
