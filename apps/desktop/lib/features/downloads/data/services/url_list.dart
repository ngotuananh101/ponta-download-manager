/// Parses pasted text into download URLs, one per line.
///
/// Blank lines and lines that are not http(s) URLs are dropped;
/// duplicates are removed, keeping the first occurrence.
List<String> parseUrlList(String text) {
  final seen = <String>{};
  final urls = <String>[];
  for (final line in text.split('\n')) {
    final url = line.trim();
    if (url.isEmpty) continue;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') &&
        !lower.startsWith('https://')) {
      continue;
    }
    if (seen.add(url)) urls.add(url);
  }
  return urls;
}
