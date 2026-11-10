import 'package:pdm_engine/pdm_engine.dart';
import 'package:test/test.dart';

void main() {
  group('parseCliArgs', () {
    test('no args shows help', () {
      expect(parseCliArgs([]).command, 'help');
    });
    test('--version shows version', () {
      expect(parseCliArgs(['--version']).command, 'version');
    });
    test('download captures the url', () {
      final result =
          parseCliArgs(['download', 'https://example.com/f.zip']);
      expect(result.command, 'download');
      expect(result.url, 'https://example.com/f.zip');
    });
    test('download without url shows help', () {
      expect(parseCliArgs(['download']).command, 'help');
    });
  });

  group('EngineConfig', () {
    test('defaults are sane', () {
      const config = EngineConfig();
      expect(config.downloadDirectory, 'downloads');
      expect(config.maxConcurrentDownloads, 3);
      expect(config.maxConnectionsPerDownload, 8);
    });
  });
}
