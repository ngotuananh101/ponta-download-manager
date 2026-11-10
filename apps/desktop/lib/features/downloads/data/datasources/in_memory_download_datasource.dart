import 'dart:async';
import 'package:pdm/features/downloads/domain/entities/download.dart';

/// In-memory stand-in for the engine IPC datasource (M3).
/// Lets the UI run end to end before the engine exists.
class InMemoryDownloadDatasource {
  final _controller = StreamController<List<Download>>.broadcast();
  List<Download> _downloads = const [];

  Stream<List<Download>> watchDownloads() async* {
    yield _downloads;
    yield* _controller.stream;
  }

  void addDownload(Download download) {
    _downloads = [..._downloads, download];
    _controller.add(_downloads);
  }

  void updateDownload(Download download) {
    _downloads = [
      for (final item in _downloads)
        if (item.id == download.id) download else item,
    ];
    _controller.add(_downloads);
  }

  void dispose() {
    _controller.close();
  }
}
