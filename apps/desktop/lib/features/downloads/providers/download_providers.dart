import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdm/features/downloads/data/datasources/in_memory_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';
import 'package:pdm/features/downloads/domain/usecases/get_downloads.dart';

final downloadDatasourceProvider =
    Provider<InMemoryDownloadDatasource>((ref) {
  final datasource = InMemoryDownloadDatasource();
  ref.onDispose(datasource.dispose);
  return datasource;
});

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepositoryImpl(ref.watch(downloadDatasourceProvider));
});

final getDownloadsProvider = Provider<GetDownloads>((ref) {
  return GetDownloads(ref.watch(downloadRepositoryProvider));
});
