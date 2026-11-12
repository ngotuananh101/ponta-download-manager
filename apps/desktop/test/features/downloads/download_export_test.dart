import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/download_export.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

void main() {
  test('exportUrls joins the URLs one per line', () {
    const downloads = [
      Download(
        id: 'dl-1',
        url: 'http://example.com/a.bin',
        fileName: 'a.bin',
        state: DownloadState.completed,
        totalBytes: 100,
      ),
      Download(
        id: 'dl-2',
        url: 'http://example.com/b.bin',
        fileName: 'b.bin',
        state: DownloadState.downloading,
        totalBytes: 200,
      ),
    ];
    expect(
      exportUrls(downloads),
      'http://example.com/a.bin\nhttp://example.com/b.bin\n',
    );
  });

  test('exportUrls returns an empty string for no downloads', () {
    expect(exportUrls(const []), isEmpty);
  });
}
