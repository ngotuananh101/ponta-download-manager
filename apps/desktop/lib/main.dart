import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdm/app/app.dart';
import 'package:pdm/core/services/linux_desktop_service.dart';
import 'package:pdm/core/services/window_service.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LinuxDesktopService.ensureDesktopIntegration();

  // The engine runs in this process: open it, start the IPC server
  // for the browser extension, and start the tray + window listener
  // before the first frame. The container is created here so the
  // services start exactly once, outside the widget tree.
  final container = ProviderContainer();
  container.read(downloadDatasourceProvider);
  await container.read(engineIpcHostProvider.future);
  container.read(windowServiceProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PdmApp(),
    ),
  );
}
