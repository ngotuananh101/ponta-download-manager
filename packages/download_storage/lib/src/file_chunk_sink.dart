import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('FileChunkSink');

/// File-backed [ChunkSink]: one coordinated writer (§6.2) writing to a
/// partial file, renamed to the final path on [finish] (§6.4).
class FileChunkSink implements ChunkSink {
  FileChunkSink._(
    this._file, {
    required this.filePath,
    required this.partialPath,
  });

  /// Creates a new partial file exclusively. Throws [DownloadError]
  /// (`file-exists`) when the final path already exists, unless
  /// [overwrite] is set, or when the partial file already exists.
  static Future<FileChunkSink> create({
    required String directory,
    required String fileName,
    bool overwrite = false,
  }) async {
    final finalPath = p.join(directory, fileName);
    final partialPath = '$finalPath.partial';
    await Directory(directory).create(recursive: true);
    if (!overwrite && await File(finalPath).exists()) {
      throw DownloadError(
        'file-exists',
        'Destination already exists: $finalPath',
      );
    }
    try {
      await File(partialPath).create(exclusive: true);
    } on FileSystemException {
      throw DownloadError(
        'file-exists',
        'Partial file already exists: $partialPath',
      );
    }
    final file = await File(partialPath).open(mode: FileMode.append);
    _log.fine('Created partial file $partialPath');
    return FileChunkSink._(file, filePath: finalPath, partialPath: partialPath);
  }

  /// Reopens an existing partial file without truncating it, so a
  /// download can resume writing at its offsets.
  ///
  /// Uses [FileMode.append]: on Dart 3.13 [FileMode.writeOnly] truncates
  /// an existing file on open, while append preserves it and honors
  /// [RandomAccessFile.setPosition] (verified with a local probe).
  ///
  /// Throws [DownloadError] (`partial-missing`) when the partial file
  /// is gone: opening in append mode would otherwise silently create
  /// an empty file, and the resumed segments would then write into
  /// offsets that were never downloaded.
  static Future<FileChunkSink> openExisting({
    required String partialPath,
    required String filePath,
  }) async {
    if (!await File(partialPath).exists()) {
      throw DownloadError(
        'partial-missing',
        'Partial file does not exist: $partialPath',
      );
    }
    final file = await File(partialPath).open(mode: FileMode.append);
    return FileChunkSink._(file, filePath: filePath, partialPath: partialPath);
  }

  final RandomAccessFile _file;

  @override
  final String filePath;

  final String partialPath;

  var _queue = Future<void>.value();
  var _closed = false;
  var _finished = false;
  var _discarded = false;

  /// Current file size in bytes.
  Future<int> get length async {
    if (_finished) {
      return File(filePath).length();
    }
    if (_closed) {
      return File(partialPath).length();
    }
    return _file.length();
  }

  @override
  Future<void> write(int offset, List<int> bytes) async {
    if (_closed) {
      throw StateError('FileChunkSink is closed');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be >= 0');
    }
    if (bytes.isEmpty) {
      return;
    }
    final task = _queue.then((_) => _doWrite(offset, bytes));
    _queue = task.catchError((Object _, StackTrace _) {});
    return task;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _queue.catchError((Object _, StackTrace _) {});
    await _file.flush();
    await _file.close();
  }

  /// Flushes, closes and atomically renames the partial file to the
  /// final path. Returns the final file. Idempotent.
  Future<File> finish() async {
    if (_finished) {
      return File(filePath);
    }
    if (_discarded) {
      throw StateError('FileChunkSink was discarded');
    }
    await close();
    if (await File(filePath).exists()) {
      // Renaming over an existing destination is intentional for
      // overwrite retries (the old file stays until the new download
      // renames over it), but it must not happen silently.
      _log.warning('Overwriting existing destination $filePath');
    }
    await File(partialPath).rename(filePath);
    _finished = true;
    _log.fine('Finished $partialPath -> $filePath');
    return File(filePath);
  }

  /// Closes and deletes the partial file. Idempotent.
  Future<void> discard() async {
    if (_discarded) {
      return;
    }
    if (_finished) {
      throw StateError('FileChunkSink was already finished');
    }
    _discarded = true;
    await close();
    final partial = File(partialPath);
    if (await partial.exists()) {
      await partial.delete();
    }
  }

  Future<void> _doWrite(int offset, List<int> bytes) async {
    await _file.setPosition(offset);
    await _file.writeFrom(bytes);
  }
}
