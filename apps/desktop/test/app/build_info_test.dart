import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/app/build_info.dart';

void main() {
  test('development ignores supplied build metadata in both fields', () {
    const info = BuildInfo(
      isDevelopment: true,
      commit: '6440356c876e5a303bf53e83978730d21223e7e1',
      buildTime: '2026-11-19T02:00:00Z',
    );
    expect(info.commitText, 'Development mode');
    expect(info.buildTimeText, 'Development mode');
  });

  test('release preserves the stamped commit and timezone', () {
    const info = BuildInfo(
      isDevelopment: false,
      commit: '6440356c876e5a303bf53e83978730d21223e7e1',
      buildTime: '2026-11-19T02:00:00Z',
    );
    expect(info.commitText, '6440356c876e5a303bf53e83978730d21223e7e1');
    expect(info.buildTimeText, '2026-11-19T02:00:00Z');
  });

  test('unstamped release reports unavailable rather than development', () {
    const info = BuildInfo(isDevelopment: false, commit: '', buildTime: '');
    expect(info.commitText, 'Unavailable');
    expect(info.buildTimeText, 'Unavailable');
  });

  test('partial metadata only marks the missing field unavailable', () {
    const info = BuildInfo(
      isDevelopment: false,
      commit: '6440356 (dirty)',
      buildTime: '   ',
    );
    expect(info.commitText, '6440356 (dirty)');
    expect(info.buildTimeText, 'Unavailable');
  });

  test('release defaults consume the compile-time Dart defines', () {
    const info = BuildInfo(isDevelopment: false);
    const commit = String.fromEnvironment('PDM_BUILD_COMMIT');
    const time = String.fromEnvironment('PDM_BUILD_TIME');
    expect(info.commitText, commit.isEmpty ? 'Unavailable' : commit);
    expect(info.buildTimeText, time.isEmpty ? 'Unavailable' : time);
  });
}
