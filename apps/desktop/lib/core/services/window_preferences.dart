import 'package:pdm/features/settings/app_settings.dart';

bool shouldStartHidden(AppSettings settings, List<String> args, bool trayAvailable) =>
    trayAvailable && (args.contains('--minimized') || settings.startupState == StartupState.tray);

void applyStartupVisibility({
  required bool hidden,
  required void Function() hide,
  required void Function() show,
  required void Function() focus,
}) {
  if (hidden) {
    hide();
  } else {
    show();
    focus();
  }
}

/// Pure policy boundary: native bindings and shutdown are injected by the owner.
Future<void> applyWindowAction({
  required WindowAction action,
  required bool trayAvailable,
  required bool closing,
  required void Function() hide,
  required void Function() minimize,
  required Future<void> Function() quit,
}) async {
  if (action == WindowAction.quit || (closing && !trayAvailable)) {
    await quit();
  } else if (trayAvailable) {
    hide();
  } else {
    minimize();
  }
}
