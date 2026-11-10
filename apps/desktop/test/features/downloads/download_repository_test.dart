import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/features/downloads/data/datasources/ipc_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

class MockDatasource extends Mock implements IpcDownloadDatasource {}

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
  group('DownloadRepositoryImpl over the IPC datasource', () {
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
  });
}
