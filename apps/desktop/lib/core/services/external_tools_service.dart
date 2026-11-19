import 'dart:ffi';
import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app_data_dir.dart';

final userToolsDirectoryProvider = Provider<String>((ref) => p.join(defaultAppDataDir(), 'bin'));

final externalToolsResolverProvider = Provider<Future<ExternalTools> Function()>((ref) {
  final directory = ref.watch(userToolsDirectoryProvider);
  return () => ExternalTools.resolve(userToolsDir: directory);
});

final externalToolsUpdateServiceProvider = Provider<ExternalToolsUpdateService>((ref) {
  if (!(Platform.isLinux && Abi.current() == Abi.linuxX64 ||
      Platform.isWindows && Abi.current() == Abi.windowsX64)) {
    throw UnsupportedError('Tool updates are available on Linux x64 and Windows x64 only.');
  }
  final directory = Directory(ref.watch(userToolsDirectoryProvider));
  final client = ExternalToolReleaseClient(cacheDirectory: Directory(p.join(directory.parent.path, 'tool-release-cache')));
  final service = ExternalToolsUpdateService(releases: client,
    installer: ExternalToolInstaller(userToolsDirectory: directory, releases: client),
    resolveTools: ref.watch(externalToolsResolverProvider), isWindows: Platform.isWindows);
  ref.onDispose(service.close);
  return service;
});
