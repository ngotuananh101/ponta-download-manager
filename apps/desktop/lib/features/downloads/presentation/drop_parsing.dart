import 'package:path/path.dart' as p;
import 'package:pdm/core/services/drop_target_channel.dart';

/// What a drop carried, after parsing.
class DropParseResult {
  const DropParseResult({
    this.urls = const [],
    this.hasTorrent = false,
    this.hasOtherFile = false,
  });

  /// http(s) URLs to add as downloads, in drop order, deduped.
  final List<String> urls;

  /// A `.torrent` file was dropped (PDM does not download torrents).
  final bool hasTorrent;

  /// Some other (non-torrent) file was dropped.
  final bool hasOtherFile;
}

/// Parses dropped content into URLs and file flags.
///
/// A link can arrive as a URI in [payload.uris], as plain text in
/// [payload.text], and a drag can carry the same link in several
/// representations — so the result is deduped. Only http(s) URLs are
/// accepted. Dropped files are classified rather than added: PDM
/// downloads from URLs, not from the local files a drag might carry.
DropParseResult parseDroppedContent(DropPayload payload) {
  final urls = <String>[];
  final seen = <String>{};

  void addUrl(String candidate) {
    final url = candidate.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;
    if (seen.add(url)) urls.add(url);
  }

  for (final uri in payload.uris) {
    addUrl(uri);
  }
  for (final line in (payload.text ?? '').split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    addUrl(trimmed);
  }

  var hasTorrent = false;
  var hasOtherFile = false;
  for (final path in payload.files) {
    if (p.basename(path).toLowerCase().endsWith('.torrent')) {
      hasTorrent = true;
    } else {
      hasOtherFile = true;
    }
  }

  return DropParseResult(
    urls: urls,
    hasTorrent: hasTorrent,
    hasOtherFile: hasOtherFile,
  );
}
