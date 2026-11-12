import 'dart:io';

import 'package:path/path.dart' as p;

/// Free disk space for the filesystem holding [path], in bytes.
/// Null when it cannot be determined.
class DiskSpaceService {
  const DiskSpaceService();

  Future<int?> freeBytes(String path) async {
    try {
      if (Platform.isWindows) {
        final root = p.rootPrefix(path);
        final result = await Process.run('fsutil', [
          'volume',
          'diskfree',
          root.isEmpty ? path : root,
        ]);
        if (result.exitCode != 0) return null;
        return parseFsutil(result.stdout as String);
      }
      final avail = await Process.run('df', [
        '-k',
        '--output=avail',
        path,
      ]);
      if (avail.exitCode == 0) {
        final parsed = parseDfAvail(avail.stdout as String);
        if (parsed != null) return parsed;
      }
      final plain = await Process.run('df', ['-k', path]);
      if (plain.exitCode != 0) return null;
      return parseDf(plain.stdout as String);
    } catch (_) {
      return null;
    }
  }

  /// Parses `df -k --output=avail`: a header line, then one number
  /// (1K blocks) per line.
  static int? parseDfAvail(String output) {
    final lines = output.trim().split('\n');
    if (lines.length < 2) return null;
    final blocks = int.tryParse(lines[1].trim());
    if (blocks == null) return null;
    return blocks * 1024;
  }

  /// Parses plain `df -k`: the Available column (4th field) of the
  /// last line, in 1K blocks.
  static int? parseDf(String output) {
    final lines = output.trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final blocks = int.tryParse(fields[3]);
    if (blocks == null) return null;
    return blocks * 1024;
  }

  /// Parses `fsutil volume diskfree`: the "Total # of free bytes" line.
  static int? parseFsutil(String output) {
    for (final line in output.split('\n')) {
      final match = RegExp(
        r'Total # of free bytes\s*:\s*(\d+)',
      ).firstMatch(line);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }
}
