import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';
import 'package:pdm/features/downloads/domain/usecases/get_downloads.dart';

class MockDownloadRepository extends Mock implements DownloadRepository {}

void main() {
  group('GetDownloads', () {
    test('returns the downloads from the repository', () async {
      final repository = MockDownloadRepository();
      const downloads = [
        Download(
          id: 'd1',
          url: 'https://example.com/f.zip',
          fileName: 'f.zip',
          state: DownloadState.queued,
          totalBytes: 100,
        ),
      ];
      when(() => repository.watchDownloads())
          .thenAnswer((_) => Stream.value(downloads));
      final usecase = GetDownloads(repository);
      final result = await usecase();
      expect(result.isRight(), isTrue);
      expect(result.getOrElse((_) => const []), downloads);
    });
  });
}
