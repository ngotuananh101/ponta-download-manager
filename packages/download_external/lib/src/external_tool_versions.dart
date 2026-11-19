enum ExternalTool {
  ffmpeg('ffmpeg'),
  ytDlp('yt-dlp'),
  quickjs('qjs');

  const ExternalTool(this.executable);

  final String executable;

  String executableName({required bool isWindows}) =>
      isWindows ? '$executable.exe' : executable;

  List<String> get versionArguments =>
      this == ffmpeg ? const ['-version'] : const ['--version'];
}

final _ffmpegVersion = RegExp(r'^ffmpeg version n?(\d+(?:\.\d+)+)(?:[-\s]|$)');
final _ytDlpVersion = RegExp(r'^(\d{4}\.\d{2}\.\d{2}(?:\.\d+)?)$');
final _quickJsVersion = RegExp(
  r'^(?:QuickJS(?:-ng)?\s+(?:version\s+)?)?v?(\d+(?:\.\d+)+)(?:\s|$)',
  caseSensitive: false,
);

String? parseToolVersion(ExternalTool tool, String output) {
  final pattern = switch (tool) {
    ExternalTool.ffmpeg => _ffmpegVersion,
    ExternalTool.ytDlp => _ytDlpVersion,
    ExternalTool.quickjs => _quickJsVersion,
  };
  return pattern.firstMatch(output.trim().split('\n').first.trim())?.group(1);
}

int compareToolVersions(String a, String b) {
  final left = a.split('.').map(BigInt.parse).toList();
  final right = b.split('.').map(BigInt.parse).toList();
  for (var i = 0; i < left.length || i < right.length; i++) {
    final comparison = (i < left.length ? left[i] : BigInt.zero)
        .compareTo(i < right.length ? right[i] : BigInt.zero);
    if (comparison != 0) return comparison;
  }
  return 0;
}

bool isToolVersionCompatible(ExternalTool tool, String reported, String expected) {
  if (tool != ExternalTool.ffmpeg) return compareToolVersions(reported, expected) == 0;
  final actual = reported.split('.');
  final family = expected.split('.');
  return actual.length >= family.length &&
      actual.take(family.length).join('.') == family.join('.') &&
      compareToolVersions(reported, expected) >= 0;
}
