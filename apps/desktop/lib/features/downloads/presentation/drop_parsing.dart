import 'package:desktop_drop/desktop_drop.dart';

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
/// A drag can carry the same URL in several representations
/// (`text/uri-list`, `text/plain`, `text/html`), so the result is
/// deduped. Only http(s) URLs are accepted; `text/html` is skipped
/// because the uri-list / plain representations already carry the URL.
DropParseResult parseDroppedContent({
  required List<DropStringItem> strings,
  required List<String> fileNames,
}) {
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

  // Prefer the uri-list: it is the canonical representation of dragged
  // links. Fall back to plain text lines that parse as URLs.
  for (final item in strings) {
    if (item.mimeType == 'text/uri-list') {
      for (final line in item.value.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        addUrl(trimmed);
      }
    }
  }
  for (final item in strings) {
    if (item.mimeType == 'text/plain') {
      for (final line in item.value.split('\n')) {
        addUrl(line);
      }
    }
  }

  var hasTorrent = false;
  var hasOtherFile = false;
  for (final name in fileNames) {
    if (name.toLowerCase().endsWith('.torrent')) {
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
