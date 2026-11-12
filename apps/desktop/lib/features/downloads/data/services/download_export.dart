import 'package:pdm/features/downloads/domain/entities/download.dart';

/// The selected downloads as plain text, one URL per line (an
/// IDM-style export), with a trailing newline when non-empty.
String exportUrls(Iterable<Download> downloads) {
  final urls = downloads.map((d) => d.url).toList();
  if (urls.isEmpty) {
    return '';
  }
  return '${urls.join('\n')}\n';
}
