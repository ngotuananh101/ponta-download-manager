import 'dart:io';

import 'package:pdm_engine/src/serve_command.dart';
import 'package:test/test.dart';

void main() {
  test('writeTokenFile creates the socket parent dir when missing', () async {
    final tmp = await Directory.systemTemp.createTemp('pdm-token-dir');
    addTearDown(() => tmp.delete(recursive: true));
    final socketPath = '${tmp.path}/fresh/nested/engine.sock';
    final tokenPath = await writeTokenFile(socketPath, 'tok-123');
    expect(tokenPath, '$socketPath.token');
    expect(await File(tokenPath).readAsString(), 'tok-123');
    expect(await Directory('${tmp.path}/fresh/nested').exists(), isTrue);
  });
}
