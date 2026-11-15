import 'dart:io';

import 'package:download_platform/download_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Windows', () {
    test('uses the known folder, which follows a moved Downloads folder', () {
      expect(
        defaultDownloadDirectory(
          environment: {'USERPROFILE': r'C:\Users\me'},
          isWindows: true,
          windowsDownloads: () => r'D:\Downloads moved',
        ),
        r'D:\Downloads moved',
      );
    });

    test('falls back to USERPROFILE when the known folder is null', () {
      expect(
        defaultDownloadDirectory(
          environment: {'USERPROFILE': r'C:\Users\me'},
          isWindows: true,
          windowsDownloads: () => null,
        ),
        r'C:\Users\me\Downloads',
      );
    });

    test('falls back to USERPROFILE when the known folder is empty', () {
      expect(
        defaultDownloadDirectory(
          environment: {'USERPROFILE': r'C:\Users\me'},
          isWindows: true,
          windowsDownloads: () => '',
        ),
        r'C:\Users\me\Downloads',
      );
    });

    test('falls back to USERPROFILE when the known folder call throws', () {
      expect(
        defaultDownloadDirectory(
          environment: {'USERPROFILE': r'C:\Users\me'},
          isWindows: true,
          windowsDownloads: () => throw StateError('boom'),
        ),
        r'C:\Users\me\Downloads',
      );
    });

    test('strips a trailing separator from the known folder', () {
      expect(
        defaultDownloadDirectory(
          isWindows: true,
          windowsDownloads: () => r'D:\Downloads moved\',
        ),
        r'D:\Downloads moved',
      );
    });

    test('keeps a UNC known folder intact', () {
      expect(
        defaultDownloadDirectory(
          isWindows: true,
          windowsDownloads: () => r'\\nas\share\Downloads',
        ),
        r'\\nas\share\Downloads',
      );
    });

    test('keeps a non-ASCII known folder intact', () {
      expect(
        defaultDownloadDirectory(
          isWindows: true,
          windowsDownloads: () => r'D:\Tải xuống',
        ),
        r'D:\Tải xuống',
      );
    });

    test('fallback is a Windows path on any host', () {
      expect(
        defaultDownloadDirectory(
          environment: {'USERPROFILE': 'C:/Users/me'},
          isWindows: true,
          windowsDownloads: () => null,
        ),
        r'C:\Users\me\Downloads',
      );
    });

    test('falls back to a relative path when USERPROFILE is unset', () {
      expect(
        defaultDownloadDirectory(
          environment: const <String, String>{},
          isWindows: true,
          windowsDownloads: () => null,
        ),
        'Downloads',
      );
    });
  });

  group('POSIX', () {
    // These drive the POSIX parser through the isWindows seam, so they can run
    // on any host — but their fixtures assume POSIX path semantics for $HOME,
    // which a Windows host cannot provide (a temp path there is `C:\...`, and
    // the parser resolves relative values with p.posix). The POSIX branch is
    // never taken in production on Windows.
    if (Platform.isWindows) {
      return;
    }

    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('pdm-platform-test');
    });

    tearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });

    void writeUserDirs(String contents) {
      File(p.join(temp.path, 'user-dirs.dirs')).writeAsStringSync(contents);
    }

    Map<String, String> env() => {
      'HOME': '/home/me',
      'XDG_CONFIG_HOME': temp.path,
    };

    test('reads XDG_DOWNLOAD_DIR and expands \$HOME', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="\$HOME/Tai xuong"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Tai xuong',
      );
    });

    test('expands the \${HOME} form', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="\${HOME}/tai"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/tai',
      );
    });

    test('accepts an absolute path', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="/mnt/disk/tai"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/mnt/disk/tai',
      );
    });

    test('resolves a relative path against \$HOME', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="Documents/Tai"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Documents/Tai',
      );
    });

    test('keeps a non-ASCII directory intact', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="\$HOME/Tải xuống"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Tải xuống',
      );
    });

    test('falls back to \$HOME/Downloads when the file is missing', () {
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('falls back when the key is absent', () {
      writeUserDirs('XDG_DESKTOP_DIR="\$HOME/Desktop"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('falls back when the directory is disabled (\$HOME itself)', () {
      writeUserDirs('XDG_DOWNLOAD_DIR="\$HOME"\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('falls back when the value is empty', () {
      writeUserDirs('XDG_DOWNLOAD_DIR=""\n');
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('tolerates comment lines and CRLF', () {
      writeUserDirs(
        '# written by xdg-user-dirs-update\r\nXDG_DOWNLOAD_DIR="/mnt/y"\r\n',
      );
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/mnt/y',
      );
    });

    test('falls back when user-dirs.dirs is a directory', () {
      Directory(p.join(temp.path, 'user-dirs.dirs')).createSync();
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('falls back when user-dirs.dirs is not UTF-8', () {
      File(p.join(temp.path, 'user-dirs.dirs'))
          .writeAsBytesSync([0xff, 0xfe, 0x2f, 0x78, 0x0a]);
      expect(
        defaultDownloadDirectory(environment: env(), isWindows: false),
        '/home/me/Downloads',
      );
    });

    test('uses \$HOME/.config when XDG_CONFIG_HOME is unset', () {
      final tempHome = Directory.systemTemp.createTempSync('pdm-home');
      addTearDown(() => tempHome.deleteSync(recursive: true));
      Directory(p.join(tempHome.path, '.config')).createSync();
      File(p.join(tempHome.path, '.config', 'user-dirs.dirs'))
          .writeAsStringSync('XDG_DOWNLOAD_DIR="\$HOME/tai"\n');
      expect(
        defaultDownloadDirectory(
          environment: {'HOME': tempHome.path},
          isWindows: false,
        ),
        p.join(tempHome.path, 'tai'),
      );
    });

    test('falls back when HOME is unset', () {
      expect(
        defaultDownloadDirectory(
          environment: const <String, String>{},
          isWindows: false,
        ),
        p.posix.join('.', 'Downloads'),
      );
    });
  });

  group('Windows host smoke test', () {
    // The only test that exercises the real FFI call. Every other Windows test
    // goes through the windowsDownloads seam, so a broken SHGetKnownFolderPath
    // binding (DLL resolution, GUID layout, COM apartment) would pass CI and
    // then silently fall back on a user's machine.
    test(
      'windowsKnownDownloads resolves an absolute path',
      () {
        final resolved = windowsKnownDownloads();
        expect(resolved, isNotNull);
        expect(p.windows.isAbsolute(resolved!), isTrue);
        expect(
          defaultDownloadDirectory(),
          p.windows.normalize(resolved),
        );
      },
      testOn: 'windows',
    );
  });
}
