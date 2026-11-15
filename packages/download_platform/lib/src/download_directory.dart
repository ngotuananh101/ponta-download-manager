import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// The user's Downloads directory as the OS reports it.
///
/// Windows: the `Downloads` known folder (`SHGetKnownFolderPath`), so a
/// folder moved via Properties → Location is followed; falls back to
/// `%USERPROFILE%\Downloads` when the call fails or returns nothing.
///
/// POSIX: `XDG_DOWNLOAD_DIR` from `user-dirs.dirs`; falls back to
/// `$HOME/Downloads` when the file or key is missing, when the value cannot
/// be read, or when it points at `$HOME` itself (xdg-user-dirs' way of saying
/// the directory is disabled).
///
/// [environment], [isWindows] and [windowsDownloads] are test seams,
/// defaulting to [Platform.environment], [Platform.isWindows] and the win32
/// call (which cannot run off Windows).
String defaultDownloadDirectory({
  Map<String, String>? environment,
  bool? isWindows,
  String? Function()? windowsDownloads,
}) {
  final env = environment ?? Platform.environment;
  if (isWindows ?? Platform.isWindows) {
    String? known;
    try {
      known = (windowsDownloads ?? windowsKnownDownloads)();
    } on Object {
      known = null;
    }
    if (known != null && known.isNotEmpty) {
      return p.windows.normalize(known);
    }
    return p.windows.normalize(
      p.windows.join(env['USERPROFILE'] ?? '.', 'Downloads'),
    );
  }
  final home = env['HOME'] ?? '.';
  return xdgDownloadDirectory(
        home: home,
        configHome: env['XDG_CONFIG_HOME'],
      ) ??
      p.posix.join(home, 'Downloads');
}

/// The Windows `Downloads` known folder, or null when it cannot be resolved.
/// Returns null off Windows: the win32 DLLs are resolved lazily, so the call
/// throws there and the throw is caught.
String? windowsKnownDownloads() {
  final id = FOLDERID_Downloads.toNative(allocator: calloc);
  try {
    final path = SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, null);
    try {
      final value = path.toDartString();
      return value.isEmpty ? null : value;
    } finally {
      CoTaskMemFree(path);
    }
  } on Object {
    return null;
  } finally {
    calloc.free(id);
  }
}

/// `XDG_DOWNLOAD_DIR` from `<configHome>/user-dirs.dirs`, or null when it is
/// missing, unreadable, empty, disabled, or the file cannot be parsed.
String? xdgDownloadDirectory({required String home, String? configHome}) {
  final base = (configHome != null && configHome.isNotEmpty)
      ? configHome
      : p.posix.join(home, '.config');
  final String contents;
  try {
    contents = File(p.posix.join(base, 'user-dirs.dirs')).readAsStringSync();
  } on FileSystemException {
    return null;
  }
  const key = 'XDG_DOWNLOAD_DIR=';
  for (final line in contents.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(key)) {
      continue;
    }
    var value = trimmed.substring(key.length).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    value = value
        .replaceAll(r'${HOME}', home)
        .replaceAll(r'$HOME', home);
    if (value.isEmpty) {
      return null;
    }
    final resolved = p.posix.normalize(
      p.posix.isAbsolute(value) ? value : p.posix.join(home, value),
    );
    if (resolved == p.posix.normalize(home)) {
      return null;
    }
    return resolved;
  }
  return null;
}
