import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

part 'downloads_provider.g.dart';

@riverpod
class Downloads extends _$Downloads {
  @override
  Future<List<Download>> build() async {
    final getDownloads = ref.watch(getDownloadsProvider);
    final result = await getDownloads();
    return result.fold(
      (failure) => throw Exception(failure.message),
      (downloads) => downloads,
    );
  }

  Future<void> addDownload(String url) async {
    final repository = ref.read(downloadRepositoryProvider);
    final result = await repository.addDownload(url);
    result.fold(
      (failure) =>
          state = AsyncError(Exception(failure.message), StackTrace.current),
      (_) => ref.invalidateSelf(),
    );
  }
}
