import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the first free destination for a download: [destination]
/// itself when it is not taken, otherwise `<stem> (1)<ext>`,
/// `<stem> (2)<ext>`, ... A trailing ` (N)` suffix on the stem is
/// stripped first, so re-downloading `file (1).ext` continues at
/// `file (2).ext` instead of producing `file (1) (1).ext`. The
/// extension is the part after the last dot; dotfiles and
/// extension-less names have none. [isTaken] defaults to checking
/// the file system.
String resolveUniquePath(
  String destination, {
  bool Function(String path)? isTaken,
}) {
  final taken = isTaken ?? (path) => File(path).existsSync();
  if (!taken(destination)) return destination;
  final dir = p.dirname(destination);
  final name = p.basename(destination);
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  final base = stem.replaceFirst(RegExp(r' \(\d+\)$'), '');
  var n = 1;
  while (true) {
    final candidate = p.join(dir, '$base ($n)$ext');
    if (!taken(candidate)) return candidate;
    n++;
  }
}
