import 'dart:io';

/// Builds the content of a Netscape-format cookies file from a
/// `name=value; ...` cookie header value, for [url].
///
/// The file starts with the '# Netscape HTTP Cookie File' header line
/// that yt-dlp requires. Each cookie then becomes one line:
///
/// `<domain>\tTRUE\t/\t<secure>\t0\t<name>\t<value>`
///
/// where the domain is the URL host with a leading dot (subdomain
/// matching) and secure is TRUE for https URLs, FALSE otherwise.
/// Parts without an `=` are skipped; values keep their `=` signs
/// (split on the first one).
String buildNetscapeCookies({
  required String cookieHeader,
  required Uri url,
}) {
  final domain = '.${url.host}';
  final secure = url.isScheme('https') ? 'TRUE' : 'FALSE';
  final lines = <String>[];
  for (final part in cookieHeader.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final equals = trimmed.indexOf('=');
    if (equals == -1) {
      continue;
    }
    final name = _sanitize(trimmed.substring(0, equals).trim());
    final value = _sanitize(trimmed.substring(equals + 1).trim());
    if (name.isEmpty) {
      continue;
    }
    lines.add('$domain\tTRUE\t/\t$secure\t0\t$name\t$value');
  }
  // yt-dlp (MozillaCookieJar) rejects the file unless its first line
  // is the Netscape header.
  return '# Netscape HTTP Cookie File\n' + lines.map((line) => '$line\n').join();
}

/// Strips tab/line-break characters that would corrupt a
/// Netscape-format line.
String _sanitize(String value) =>
    value.replaceAll(RegExp(r'[\t\r\n]'), '');

/// A temporary cookies file for one yt-dlp run, in a fresh
/// system-temp directory. [delete] removes the whole directory.
/// The file is never logged and holds only the cookies for one run.
class TempCookieFile {
  TempCookieFile._(this.directory, this.file);

  final Directory directory;
  final File file;

  factory TempCookieFile.create({
    required String cookieHeader,
    required Uri url,
  }) {
    final directory =
        Directory.systemTemp.createTempSync('pdm-cookies-');
    final file = File('${directory.path}/cookies.txt');
    file.writeAsStringSync(
      buildNetscapeCookies(cookieHeader: cookieHeader, url: url),
    );
    return TempCookieFile._(directory, file);
  }

  /// Best-effort delete of the temp directory (and the file in it).
  void delete() {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {
      // Best effort: the directory may already be gone.
    }
  }
}

/// Removes cookie material from a yt-dlp output line before it is
/// surfaced (error messages reach the UI): the temp cookies file path
/// is replaced, and any `Cookie:` header material is redacted.
String scrubCookieMaterial(String line, String? cookieFilePath) {
  var result = line;
  if (cookieFilePath != null && cookieFilePath.isNotEmpty) {
    result = result.replaceAll(cookieFilePath, '<cookies-file>');
  }
  final index = result.toLowerCase().indexOf('cookie:');
  if (index != -1) {
    result = '${result.substring(0, index)}Cookie: <redacted>';
  }
  return result;
}
