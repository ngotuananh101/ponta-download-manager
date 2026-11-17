import 'dart:io';

/// TEMPORARY: evidence gathering for the Windows "tray click does not bring the
/// window back" bug.
///
/// The app has no logging sink, so failures inside the tray listeners are
/// invisible. This appends one line per observation to a file in the system
/// temporary directory, which is the only way to tell the two candidate causes
/// apart on the machine where the bug reproduces:
///
///  * `currentWindow() == null` when the window is hidden: the tray event did
///    arrive, but `_showWindow()` returned before touching the window.
///  * the window resolves and `show()` runs, yet `isVisible` stays false: the
///    native call is being refused.
///
/// Delete this file and its call sites once the cause is confirmed.
const String _kLogFileName = 'pdm-tray-diag.log';

/// Appends [message] to the diagnostic log, with a timestamp.
///
/// Never throws: a diagnostic that breaks the thing it measures is worthless.
Future<void> trayDiag(String message) async {
  try {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$_kLogFileName',
    );
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // A diagnostic never interferes with the app.
  }
}

/// The absolute path of the diagnostic log, for reporting it to the user.
String get trayDiagPath =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$_kLogFileName';
