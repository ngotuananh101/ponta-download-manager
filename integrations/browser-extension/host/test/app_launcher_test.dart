import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm_native_host/src/app_launcher.dart';
import 'package:test/test.dart';

class MockIpcClient extends Mock implements IpcClient {}

void main() {
  group('appPathFromDesktopContent', () {
    test('parses an unquoted Exec line with %u', () {
      expect(
        appPathFromDesktopContent(
          '[Desktop Entry]\nExec=/opt/pdm/pdm %u\nIcon=com.ponta.pdm\n',
        ),
        '/opt/pdm/pdm',
      );
    });

    test('parses a quoted Exec line with %u', () {
      expect(
        appPathFromDesktopContent(
          '[Desktop Entry]\nExec="/home/user/My Apps/pdm" %u\n',
        ),
        '/home/user/My Apps/pdm',
      );
    });

    test('parses an Exec line without arguments', () {
      expect(
        appPathFromDesktopContent('[Desktop Entry]\nExec=/opt/pdm/pdm\n'),
        '/opt/pdm/pdm',
      );
    });

    test('returns null when there is no Exec line', () {
      expect(
        appPathFromDesktopContent('[Desktop Entry]\nName=PDM\n'),
        isNull,
      );
    });
  });

  group('AppLauncher', () {
    late Directory tempDir;
    late String socketPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-launcher-test-');
      socketPath = '${tempDir.path}/engine.sock';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    AppLauncher launcher({
      String? desktopFilePath,
      Map<String, String>? environment,
      Future<void> Function(String path)? processStarter,
      Duration timeout = const Duration(seconds: 2),
    }) {
      return AppLauncher(
        socketPath: socketPath,
        desktopFilePath: desktopFilePath,
        environment: environment ?? const {},
        processStarter: processStarter,
        timeout: timeout,
      );
    }

    Future<String> writeDesktopFile(String execLine) async {
      final file = File('${tempDir.path}/com.ponta.pdm.desktop');
      await file.writeAsString('[Desktop Entry]\n$execLine\n');
      return file.path;
    }

    test('resolveAppPath prefers PDM_APP_PATH over the desktop file',
        () async {
      await writeDesktopFile('Exec=/opt/pdm/pdm %u');
      final found = launcher(
        environment: {'PDM_APP_PATH': '/custom/pdm'},
      ).resolveAppPath();
      expect(found, '/custom/pdm');
    });

    test('resolveAppPath falls back to the desktop Exec line', () async {
      final path = await writeDesktopFile('Exec="/opt/pdm/pdm" %u');
      final found = launcher(desktopFilePath: path).resolveAppPath();
      expect(found, '/opt/pdm/pdm');
    });

    test('resolveAppPath returns null when nothing is configured',
        () async {
      final found = launcher(
        desktopFilePath: '${tempDir.path}/missing.desktop',
      ).resolveAppPath();
      expect(found, isNull);
    });

    test('waitForEndpoint returns true once the token and socket appear',
        () async {
      final l = launcher();
      final waiting = l.waitForEndpoint();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await File('$socketPath.token').writeAsString('tok');
      await File(socketPath).writeAsString('');
      expect(await waiting, isTrue);
    });

    test('waitForEndpoint returns false on timeout', () async {
      final l = launcher(timeout: const Duration(milliseconds: 100));
      expect(await l.waitForEndpoint(), isFalse);
    });

    test('launchAndWait returns false when no app path is configured',
        () async {
      final l = launcher(
        desktopFilePath: '${tempDir.path}/missing.desktop',
      );
      expect(await l.launchAndWait(), isFalse);
    });

    test('launchAndWait returns true without launching when the app is '
        'already running', () async {
      var started = 0;
      await File('$socketPath.token').writeAsString('tok');
      await File(socketPath).writeAsString('');
      final l = launcher(
        processStarter: (_) async {
          started++;
        },
      );
      expect(await l.launchAndWait(), isTrue);
      expect(started, 0);
    });

    test('launchAndWait starts the app and waits for the endpoint',
        () async {
      final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
      final started = <String>[];
      final l = launcher(
        desktopFilePath: path,
        processStarter: (appPath) async {
          started.add(appPath);
          // Simulate the app starting: create the endpoint shortly
          // after being launched.
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 100),
                () async {
              await File('$socketPath.token').writeAsString('tok');
              await File(socketPath).writeAsString('');
            }),
          );
        },
      );
      expect(await l.launchAndWait(), isTrue);
      expect(started, ['/opt/pdm/pdm']);
    });

    test('launchAndWait returns false when the starter throws', () async {
      final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
      final l = launcher(
        desktopFilePath: path,
        processStarter: (_) async {
          throw const FileSystemException('no such binary');
        },
      );
      expect(await l.launchAndWait(), isFalse);
    });
  });

  group('connectWithAutoLaunch', () {
    late Directory tempDir;
    late String socketPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-launcher-test-');
      socketPath = '${tempDir.path}/engine.sock';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('connects on the first try without launching', () async {
      final client = MockIpcClient();
      var launches = 0;
      final result = await connectWithAutoLaunch(
        connect: () async => client,
        launcher: AppLauncher(
          socketPath: socketPath,
          environment: const {},
          processStarter: (_) async {
            launches++;
          },
        ),
      );
      expect(result, same(client));
      expect(launches, 0);
    });

    test('launches the app and retries when the first connect fails',
        () async {
      final client = MockIpcClient();
      var connects = 0;
      var launches = 0;
      final desktopFile = File('${tempDir.path}/com.ponta.pdm.desktop');
      await desktopFile.writeAsString(
        '[Desktop Entry]\nExec=/opt/pdm/pdm %u\n',
      );
      final result = await connectWithAutoLaunch(
        connect: () async {
          connects++;
          if (connects == 1) {
            throw const FileSystemException('token file missing');
          }
          return client;
        },
        launcher: AppLauncher(
          socketPath: socketPath,
          desktopFilePath: desktopFile.path,
          environment: const {},
          processStarter: (_) async {
            launches++;
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 50),
                () async {
                  await File('$socketPath.token').writeAsString('tok');
                  await File(socketPath).writeAsString('');
                },
              ),
            );
          },
          timeout: const Duration(seconds: 2),
        ),
      );
      expect(result, same(client));
      expect(connects, 2);
      expect(launches, 1);
    });

    test('throws a clear error when the app cannot be launched', () async {
      await expectLater(
        connectWithAutoLaunch(
          connect: () async {
            throw const FileSystemException('token file missing');
          },
          launcher: AppLauncher(
            socketPath: socketPath,
            desktopFilePath: '${tempDir.path}/missing.desktop',
            environment: const {},
            timeout: const Duration(milliseconds: 50),
          ),
        ),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'connection-closed',
          ),
        ),
      );
    });
  });
}
