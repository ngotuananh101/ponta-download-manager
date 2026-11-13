import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/app/app.dart';
import 'package:pdm/app/startup_error_app.dart';
import 'package:pdm/core/services/linux_desktop_service.dart';
import 'package:pdm/core/services/window_api.dart';
import 'package:pdm/core/services/window_service.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _startApp(args);
  } catch (e) {
    // Startup failed before the first frame (engine, IPC server, or
    // window setup): show the error instead of dying silently.
    runApp(StartupErrorApp(message: e.toString()));
  }
}

Future<void> _startApp(List<String> args) async {
  await LinuxDesktopService.ensureDesktopIntegration();

  // The engine runs in this process: open it, start the IPC server
  // for the browser extension, and start the tray + window listener
  // before the first frame. The container is created here so the
  // services start exactly once, outside the widget tree.
  final container = ProviderContainer();
  container.read(downloadDatasourceProvider);
  await container.read(engineIpcHostProvider.future);
  container.read(windowServiceProvider);

  // The app draws its own header bar (AppHeader), so the window
  // carries no native title bar. On Linux the runner already created
  // it undecorated; on other platforms that is done here (asking
  // nativeapi for a hidden title bar on Linux switches on its
  // custom-shadow mode, which 0.5.10 gets the geometry of wrong).
  // The Dart side must also honour --minimized: the runner alone
  // cannot stop this show() from presenting the window on auto-start.
  final isMinimized = args.contains('--minimized');
  whenCurrentWindow((window) {
    if (!Platform.isLinux) {
      window.titleBarStyle = TitleBarStyle.hidden;
      window.isWindowControlButtonsVisible = false;
    }
    window.title = 'Ponta Download Manager';
    window.setSize(const Size(950, 650).toNative(), false);
    window.minimumSize = const Size(950, 650).toNative();
    window.backgroundColor = Colors.transparent.toNative();
    window.center();
    if (!isMinimized) {
      window.show();
      window.focus();
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PdmApp(),
    ),
  );
}
