import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('defaultSocketPath ends with pdm/engine.sock', () {
    expect(defaultSocketPath(), endsWith(p.join('pdm', 'engine.sock')));
  });
}
