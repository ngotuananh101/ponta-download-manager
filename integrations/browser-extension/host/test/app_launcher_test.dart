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
      expect(appPathFromDesktopContent('[Desktop Entry]\nName=PDM\n'), isNull);
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
      String? hostExecutablePath,
      Map<String, String>? environment,
      Future<void> Function(String path)? processStarter,
      Duration timeout = const Duration(seconds: 2),
      bool? isWindows,
    }) {
      return AppLauncher(
        socketPath: socketPath,
        desktopFilePath: desktopFilePath,
        hostExecutablePath:
            hostExecutablePath ?? '${tempDir.path}/bin/pdm-native-host',
        environment: environment ?? const {},
        processStarter: processStarter,
        timeout: timeout,
        isWindows: isWindows,
      );
    }

    Future<String> writeDesktopFile(String execLine) async {
      final file = File('${tempDir.path}/com.ponta.pdm.desktop');
      await file.writeAsString('[Desktop Entry]\n$execLine\n');
      return file.path;
    }

    test('resolveAppPath prefers PDM_APP_PATH over the bundled sibling '
        'and desktop file', () async {
      final hostFile = File('${tempDir.path}/bundle/bin/pdm-native-host');
      final appFile = File('${tempDir.path}/bundle/pdm');
      await hostFile.parent.create(recursive: true);
      await hostFile.writeAsString('');
      await appFile.writeAsString('');
      final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
      final found = launcher(
        desktopFilePath: path,
        hostExecutablePath: hostFile.path,
        environment: {'PDM_APP_PATH': '/custom/pdm'},
      ).resolveAppPath();
      expect(found, '/custom/pdm');
    });

    test('resolveAppPath resolves the bundled sibling binary on Linux '
        'before the desktop file', () async {
      final hostFile = File('${tempDir.path}/bundle/bin/pdm-native-host');
      final appFile = File('${tempDir.path}/bundle/pdm');
      await hostFile.parent.create(recursive: true);
      await hostFile.writeAsString('');
      await appFile.writeAsString('');
      final desktopPath = await writeDesktopFile('Exec=/opt/pdm/pdm %u');

      final found = launcher(
        desktopFilePath: desktopPath,
        hostExecutablePath: hostFile.path,
      ).resolveAppPath();

      expect(found, appFile.path);
    });

    test(
      'resolveAppPath resolves the bundled sibling binary on Windows',
      () async {
        final hostFile = File('${tempDir.path}/bundle/bin/pdm-native-host.exe');
        final appFile = File('${tempDir.path}/bundle/pdm.exe');
        await hostFile.parent.create(recursive: true);
        await hostFile.writeAsString('');
        await appFile.writeAsString('');

        final found = launcher(
          desktopFilePath: '${tempDir.path}/missing.desktop',
          hostExecutablePath: hostFile.path,
          isWindows: true,
        ).resolveAppPath();

        expect(found, appFile.path);
      },
    );

    test('resolveAppPath falls back to the desktop Exec line when a '
        'staged host has no bundled sibling', () async {
      final stagedHost = File(
        '${tempDir.path}/.local/share/pdm/browser-integration/bin/pdm-native-host',
      );
      await stagedHost.parent.create(recursive: true);
      await stagedHost.writeAsString('');
      final path = await writeDesktopFile('Exec="/opt/pdm/pdm.AppImage" %u');
      final found = launcher(
        desktopFilePath: path,
        hostExecutablePath: stagedHost.path,
      ).resolveAppPath();
      expect(found, '/opt/pdm/pdm.AppImage');
    });

    test(
      'resolveAppPath ignores an empty PDM_APP_PATH and uses the bundle',
      () async {
        final appFile = File('${tempDir.path}/pdm');
        await appFile.writeAsString('');

        final found = launcher(
          environment: {'PDM_APP_PATH': ''},
        ).resolveAppPath();

        expect(found, appFile.path);
      },
    );

    test(
      'resolveAppPath does not treat a directory as a bundled binary',
      () async {
        await Directory('${tempDir.path}/pdm').create();
        final path = await writeDesktopFile('Exec=/opt/pdm/pdm.AppImage %u');

        final found = launcher(desktopFilePath: path).resolveAppPath();

        expect(found, '/opt/pdm/pdm.AppImage');
      },
    );

    test('launchAndWait launches the bundled Windows app without a '
        'desktop file', () async {
      final hostFile = File('${tempDir.path}/bundle/bin/pdm-native-host.exe');
      final appFile = File('${tempDir.path}/bundle/pdm.exe');
      await hostFile.parent.create(recursive: true);
      await hostFile.writeAsString('');
      await appFile.writeAsString('');
      final started = <String>[];
      final l = launcher(
        desktopFilePath: '${tempDir.path}/missing.desktop',
        hostExecutablePath: hostFile.path,
        isWindows: true,
        processStarter: (appPath) async {
          started.add(appPath);
          await File('$socketPath.token').writeAsString('tok');
          await File('$socketPath.port').writeAsString('47931');
        },
      );

      expect(await l.launchAndWait(), isTrue);
      expect(started, [appFile.path]);
    });

    test('resolveAppPath falls back to the desktop Exec line', () async {
      final path = await writeDesktopFile('Exec="/opt/pdm/pdm" %u');
      final found = launcher(desktopFilePath: path).resolveAppPath();
      expect(found, '/opt/pdm/pdm');
    });

    test('resolveAppPath returns null when nothing is configured', () async {
      final found = launcher(
        desktopFilePath: '${tempDir.path}/missing.desktop',
      ).resolveAppPath();
      expect(found, isNull);
    });

    for (final xdgDataHome in [null, '']) {
      test('resolveAppPath uses HOME when XDG_DATA_HOME is '
          '${xdgDataHome == null ? 'unset' : 'empty'}', () async {
        final desktopFile = File(
          '${tempDir.path}/.local/share/applications/com.ponta.pdm.desktop',
        );
        await desktopFile.parent.create(recursive: true);
        await desktopFile.writeAsString(
          '[Desktop Entry]\nExec="/opt/PDM/pdm.AppImage" %u\n',
        );

        final found = launcher(
          environment: {'HOME': tempDir.path, 'XDG_DATA_HOME': ?xdgDataHome},
        ).resolveAppPath();

        expect(found, '/opt/PDM/pdm.AppImage');
      });
    }

    test('resolveAppPath uses a nonempty XDG_DATA_HOME', () async {
      final desktopFile = File(
        '${tempDir.path}/data/applications/com.ponta.pdm.desktop',
      );
      await desktopFile.parent.create(recursive: true);
      await desktopFile.writeAsString(
        '[Desktop Entry]\nExec=/opt/pdm/pdm.AppImage %u\n',
      );

      final found = launcher(
        environment: {
          'HOME': '${tempDir.path}/home',
          'XDG_DATA_HOME': '${tempDir.path}/data',
        },
      ).resolveAppPath();

      expect(found, '/opt/pdm/pdm.AppImage');
    });

    test(
      'waitForEndpoint returns true once the token and socket appear',
      () async {
        final l = launcher();
        final waiting = l.waitForEndpoint();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await File('$socketPath.token').writeAsString('tok');
        await File(socketPath).writeAsString('');
        expect(await waiting, isTrue);
      },
    );

    test('waitForEndpoint returns true once the token and port file appear '
        'on Windows', () async {
      final l = launcher(isWindows: true);
      final waiting = l.waitForEndpoint();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await File('$socketPath.token').writeAsString('tok');
      await File('$socketPath.port').writeAsString('47931');
      expect(await waiting, isTrue);
    });

    test(
      'a socket file alone does not count as an endpoint on Windows',
      () async {
        final l = launcher(
          isWindows: true,
          timeout: const Duration(milliseconds: 100),
        );
        await File('$socketPath.token').writeAsString('tok');
        await File(socketPath).writeAsString('');
        expect(await l.waitForEndpoint(), isFalse);
      },
    );

    test('waitForEndpoint returns false on timeout', () async {
      final l = launcher(timeout: const Duration(milliseconds: 100));
      expect(await l.waitForEndpoint(), isFalse);
    });

    test(
      'launchAndWait returns false when no app path is configured',
      () async {
        final l = launcher(desktopFilePath: '${tempDir.path}/missing.desktop');
        expect(await l.launchAndWait(), isFalse);
      },
    );

    test('launchAndWait returns true without launching when the app is '
        'already running', () async {
      var started = 0;
      await File('$socketPath.token').writeAsString('tok');
      final server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);
      final l = launcher(
        processStarter: (_) async {
          started++;
        },
      );
      expect(await l.launchAndWait(), isTrue);
      expect(started, 0);
    });

    test('launchAndWait returns true without launching when the app is '
        'already running on Windows', () async {
      var started = 0;
      await File('$socketPath.token').writeAsString('tok');
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      await File('$socketPath.port').writeAsString('${server.port}');
      final l = launcher(
        isWindows: true,
        processStarter: (_) async {
          started++;
        },
      );
      expect(await l.launchAndWait(), isTrue);
      expect(started, 0);
    });

    test(
      'launchAndWait launches the app when the endpoint files are stale',
      () async {
        final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
        final started = <String>[];
        // Crash leftovers: the files exist but nothing listens.
        await File('$socketPath.token').writeAsString('tok');
        await File(socketPath).writeAsString('');
        final l = launcher(
          desktopFilePath: path,
          processStarter: (appPath) async {
            started.add(appPath);
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 100), () async {
                await File('$socketPath.token').writeAsString('tok');
                await File(socketPath).writeAsString('');
              }),
            );
          },
        );
        expect(await l.launchAndWait(), isTrue);
        expect(started, ['/opt/pdm/pdm']);
      },
    );

    test(
      'launchAndWait launches the app when the port file is stale on Windows',
      () async {
        final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
        final started = <String>[];
        // A port file pointing at a closed port: crash leftovers.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final stalePort = probe.port;
        await probe.close();
        await File('$socketPath.token').writeAsString('tok');
        await File('$socketPath.port').writeAsString('$stalePort');
        final l = launcher(
          desktopFilePath: path,
          isWindows: true,
          processStarter: (appPath) async {
            started.add(appPath);
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 100), () async {
                await File('$socketPath.token').writeAsString('tok');
                await File('$socketPath.port').writeAsString('47931');
              }),
            );
          },
        );
        expect(await l.launchAndWait(), isTrue);
        expect(started, ['/opt/pdm/pdm']);
      },
    );

    test('launchAndWait starts the app and waits for the endpoint', () async {
      final path = await writeDesktopFile('Exec=/opt/pdm/pdm %u');
      final started = <String>[];
      final l = launcher(
        desktopFilePath: path,
        processStarter: (appPath) async {
          started.add(appPath);
          // Simulate the app starting: create the endpoint shortly
          // after being launched.
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 100), () async {
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

    test('launches the app and retries when the first connect fails', () async {
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
              Future<void>.delayed(const Duration(milliseconds: 50), () async {
                await File('$socketPath.token').writeAsString('tok');
                await File(socketPath).writeAsString('');
              }),
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
