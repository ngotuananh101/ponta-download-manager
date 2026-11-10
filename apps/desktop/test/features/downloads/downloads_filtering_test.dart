import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';

Download _d(
  String id, {
  String fileName = 'file',
  String url = 'https://example.com/file',
  DownloadState state = DownloadState.downloading,
  int totalBytes = 1000,
}) {
  return Download(
    id: id,
    url: url,
    fileName: fileName,
    state: state,
    totalBytes: totalBytes,
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

    test('name sorts A-Z case-insensitively', () {
      final sorted = visibleDownloads(
        items,
        sort: DownloadSort.name,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(
        sorted.map((d) => d.fileName).toList(),
        ['alpha.zip', 'beta.zip', 'delta.zip', 'gamma.zip'],
      );
    });

    test('size sorts largest first, unknown total last', () {
      final sorted = visibleDownloads(
        items,
        sort: DownloadSort.size,
        filter: DownloadFilter.all,
        query: '',
      );
      expect(sorted.map((d) => d.id).toList(), ['dl-1', 'dl-3', 'dl-2', 'dl-4']);
    });

    test('filter keeps only the matching state', () {
      final completed = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.completed,
        query: '',
      );
      expect(completed.map((d) => d.id).toList(), ['dl-1']);
      final queued = visibleDownloads(
        items,
        sort: DownloadSort.newest,
        filter: DownloadFilter.queued,
        query: '',
      );
      expect(queued.map((d) => d.id).toList(), ['dl-4']);
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
