import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

class MockDatasource extends Mock implements EngineDownloadDatasource {}

DownloadInfo info({String id = 'dl-1'}) {
  return DownloadInfo(
    id: id,
    url: 'http://127.0.0.1:9/f.bin',
    fileName: 'f.bin',
    status: DownloadStatus.queued,
    totalBytes: 1000,
  );
}

void main() {
  group('DownloadRepositoryImpl over the engine datasource', () {
    late MockDatasource datasource;
    late DownloadRepositoryImpl repository;

    setUp(() {
      datasource = MockDatasource();
      repository = DownloadRepositoryImpl(datasource);
    });

    test('addDownload rejects a non-http(s) url', () async {
      final result = await repository.addDownload('ftp://example.com/f.bin');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(
          failure.message,
          'URL must start with http:// or https://',
        ),
        (_) => fail('expected a failure'),
      );
      verifyNever(() => datasource.addDownload(any()));
    });

    test('addDownload returns the mapped download from the engine', () async {
      when(
        () => datasource.addDownload(any()),
      ).thenAnswer((_) async => info());
      final result = await repository.addDownload('http://127.0.0.1:9/f.bin');
      expect(result.isRight(), isTrue);
      final download = result.getOrElse(
        (_) => throw StateError('expected a download'),
      );
      expect(download.id, 'dl-1');
      expect(download.fileName, 'f.bin');
      expect(download.state, DownloadState.queued);
      verify(() => datasource.addDownload('http://127.0.0.1:9/f.bin'))
          .called(1);
    });

    test('probeUrl rejects a non-http(s) url', () async {
      final result = await repository.probeUrl('ftp://example.com/f.bin');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(
          failure.message,
          'URL must start with http:// or https://',
        ),
        (_) => fail('expected a failure'),
      );
      verifyNever(() => datasource.probeUrl(any()));
    });

    test('probeUrl returns the probed file name and size', () async {
      const probe = ProbeResult(
        url: 'http://127.0.0.1:9/f.bin',
        fileName: 'f.bin',
        totalBytes: 1000,
      );
      when(() => datasource.probeUrl(any())).thenAnswer((_) async => probe);
      final result =
          await repository.probeUrl('http://127.0.0.1:9/f.bin');
      expect(result.isRight(), isTrue);
      final got = result.getOrElse(
        (_) => throw StateError('expected a probe result'),
      );
      expect(got.fileName, 'f.bin');
      expect(got.totalBytes, 1000);
      verify(() => datasource.probeUrl('http://127.0.0.1:9/f.bin'))
          .called(1);
    });

    test('probeUrl maps an engine error to an unexpected failure', () async {
      when(() => datasource.probeUrl(any())).thenThrow(
        const DownloadError('network', 'connection refused'),
      );
      final result = await repository.probeUrl('http://127.0.0.1:9/f.bin');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, 'connection refused'),
        (_) => fail('expected a failure'),
      );
    });

    test('addDownload passes directory, file name and paused through',
        () async {
      when(
        () => datasource.addDownload(
          any(),
          directory: any(named: 'directory'),
          fileName: any(named: 'fileName'),
          conflictPolicy: any(named: 'conflictPolicy'),
          paused: any(named: 'paused'),
        ),
      ).thenAnswer((_) async => info());
      final result = await repository.addDownload(
        'http://127.0.0.1:9/f.bin',
        directory: '/tmp/other',
        fileName: 'g.bin',
        paused: true,
      );
      expect(result.isRight(), isTrue);
      verify(
        () => datasource.addDownload(
          'http://127.0.0.1:9/f.bin',
          directory: '/tmp/other',
          fileName: 'g.bin',
          paused: true,
        ),
      ).called(1);
    });

    test('pause maps a not-found error to a validation failure', () async {
      when(() => datasource.pauseDownload(any())).thenThrow(
        const DownloadError('not-found', 'no such download'),
      );
      final result = await repository.pauseDownload('dl-9');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, 'Download not found'),
        (_) => fail('expected a failure'),
      );
    });

    test('pause maps any other engine error to an unexpected failure',
        () async {
      when(() => datasource.pauseDownload(any())).thenThrow(
        const DownloadError('internal', 'boom'),
      );
      final result = await repository.pauseDownload('dl-1');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, 'boom'),
        (_) => fail('expected a failure'),
      );
    });

    test('setGlobalBandwidthLimit delegates to the datasource', () async {
      when(
        () => datasource.setGlobalBandwidthLimit(any()),
      ).thenAnswer((_) async {});
      expect(
        (await repository.setGlobalBandwidthLimit(8192)).isRight(),
        isTrue,
      );
      expect(
        (await repository.setGlobalBandwidthLimit(null)).isRight(),
        isTrue,
      );
      verify(() => datasource.setGlobalBandwidthLimit(8192)).called(1);
      verify(() => datasource.setGlobalBandwidthLimit(null)).called(1);
    });

    test('setGlobalBandwidthLimit maps an engine error to a failure',
        () async {
      when(() => datasource.setGlobalBandwidthLimit(any())).thenThrow(
        const DownloadError('internal', 'boom'),
      );
      final result = await repository.setGlobalBandwidthLimit(8192);
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, 'boom'),
        (_) => fail('expected a failure'),
      );
    });

    test('resume, cancel and retry delegate to the datasource', () async {
      when(() => datasource.resumeDownload(any())).thenAnswer((_) async {});
      when(() => datasource.cancelDownload(any())).thenAnswer((_) async {});
      when(() => datasource.retryDownload(any())).thenAnswer((_) async {});
      expect((await repository.resumeDownload('dl-1')).isRight(), isTrue);
      expect((await repository.cancelDownload('dl-1')).isRight(), isTrue);
      expect((await repository.retryDownload('dl-1')).isRight(), isTrue);
      verify(() => datasource.resumeDownload('dl-1')).called(1);
      verify(() => datasource.cancelDownload('dl-1')).called(1);
      verify(() => datasource.retryDownload('dl-1')).called(1);
    });

    test('setPriority forwards to the datasource', () async {
      when(
        () => datasource.setPriority(any(), any()),
      ).thenAnswer((_) async {});
      expect((await repository.setPriority('dl-1', 1)).isRight(), isTrue);
      verify(() => datasource.setPriority('dl-1', 1)).called(1);
    });

    test('deleteFile forwards to the datasource', () async {
      when(
        () => datasource.deleteFile(any()),
      ).thenAnswer((_) async {});
      expect((await repository.deleteFile('dl-1')).isRight(), isTrue);
      verify(() => datasource.deleteFile('dl-1')).called(1);
    });

    test('renameFile forwards to the datasource', () async {
      when(
        () => datasource.renameFile(any(), any()),
      ).thenAnswer((_) async {});
      expect((await repository.renameFile('dl-1', 'g.bin')).isRight(), isTrue);
      verify(() => datasource.renameFile('dl-1', 'g.bin')).called(1);
    });

    test('deleteDownload forwards the deleteFile flag', () async {
      when(
        () => datasource.deleteDownload(
          any(),
          deleteFile: any(named: 'deleteFile'),
        ),
      ).thenAnswer((_) async {});
      expect(
        (await repository.deleteDownload('dl-1', deleteFile: true)).isRight(),
        isTrue,
      );
      expect((await repository.deleteDownload('dl-1')).isRight(), isTrue);
      verify(
        () => datasource.deleteDownload('dl-1', deleteFile: true),
      ).called(1);
      verify(
        () => datasource.deleteDownload('dl-1', deleteFile: false),
      ).called(1);
    });
  });
}
