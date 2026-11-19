import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

void main() {
  test('parses only recognized stable tool versions', () {
    expect(parseToolVersion(ExternalTool.ffmpeg, 'ffmpeg version 7.0.2-static\nbuild'), '7.0.2');
    expect(parseToolVersion(ExternalTool.ffmpeg, 'ffmpeg version n9.0-12-gabc'), '9.0');
    expect(parseToolVersion(ExternalTool.ytDlp, '2026.10.26\n'), '2026.10.26');
    expect(parseToolVersion(ExternalTool.quickjs, 'QuickJS-ng version 0.18.0'), '0.18.0');
    expect(parseToolVersion(ExternalTool.quickjs, '0.18.0'), '0.18.0');
    expect(parseToolVersion(ExternalTool.ffmpeg, 'ffmpeg version N-123-gabcdef'), isNull);
    expect(parseToolVersion(ExternalTool.ytDlp, 'version unknown'), isNull);
  });

  test('accepts ffmpeg patch versions within the selected release family', () {
    expect(isToolVersionCompatible(ExternalTool.ffmpeg, '9.0.1', '9.0'), isTrue);
    expect(isToolVersionCompatible(ExternalTool.ffmpeg, '8.9.9', '9.0'), isFalse);
    expect(isToolVersionCompatible(ExternalTool.ytDlp, '2026.10.27', '2026.10.26'), isFalse);
  });
  test('compares numeric components, treating trailing zeros as equal', () {
    expect(compareToolVersions('9.0', '7.0.2'), greaterThan(0));
    expect(compareToolVersions('2026.10.01', '2026.9.30'), greaterThan(0));
    expect(compareToolVersions('0.18.0', '0.18'), 0);
  });

  test('an absent or unknown local version does not imply an update', () {
    final release = ExternalToolRelease(tool: ExternalTool.ffmpeg,
      version: '9.0', url: Uri.https('github.com', '/asset'), sha256: 'a' * 64,
      sizeBytes: 1, archiveFormat: ToolArchiveFormat.tarXz, releaseId: '1');
    ExternalToolStatus status(String? version, ExternalToolOrigin origin) =>
        ExternalToolStatus(tool: ExternalTool.ffmpeg, currentVersion: version,
          origin: origin, latest: release);
    expect(status(null, ExternalToolOrigin.missing).hasUpdate, isFalse);
    expect(status(null, ExternalToolOrigin.system).hasUpdate, isFalse);
    expect(status('7.0.2', ExternalToolOrigin.bundled).hasUpdate, isTrue);
    expect(status('9.0.0', ExternalToolOrigin.downloaded).hasUpdate, isFalse);
  });
}
