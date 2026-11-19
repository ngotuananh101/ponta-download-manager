import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/external_tools_service.dart';
import 'package:pdm/features/downloads/data/services/thumbnail_service.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

void main() {
  test('desktop engine factory and uncached thumbnails use the same live resolver', () async {
    final temp = await Directory.systemTemp.createTemp('tools-wiring-');
    final container = ProviderContainer(overrides: [
      userToolsDirectoryProvider.overrideWithValue('${temp.path}/bin'),
      externalToolsResolverProvider.overrideWithValue(() async => const ExternalTools(ffmpegPath: null, ytDlpPath: null)),
    ]);
    final factory = container.read(engineFactoryProvider);
    // Opening the factory's default DB is intentionally not part of this test.
    expect(factory, isA<Function>());
    final video = await File('${temp.path}/video.mp4').writeAsBytes([1]);
    var path = '${temp.path}/downloaded/ffmpeg';
    final used = <String>[];
    final service = ThumbnailService(cacheDir: '${temp.path}/thumbs',
      resolveTools: () async => ExternalTools(ffmpegPath: path, ytDlpPath: null),
      runProcess: (args, {timeout}) async {
        used.add(args.first);
        await File(args.last).writeAsBytes([1]);
        return ProcessResult(1, 0, '', '');
      });
    Download download(String id) => Download(id: id, url: 'https://example.invalid/video',
      fileName: 'video.mp4', filePath: video.path, state: DownloadState.completed,
      downloadedBytes: 1, totalBytes: 1);
    expect(await service.thumbnailFor(download('one')), isNotNull);
    path = '${temp.path}/bundle/ffmpeg';
    expect(await service.thumbnailFor(download('two')), isNotNull);
    expect(used, ['${temp.path}/downloaded/ffmpeg', '${temp.path}/bundle/ffmpeg']);
    container.dispose();
    await temp.delete(recursive: true);
  });
}
