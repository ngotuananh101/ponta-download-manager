import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pdm/core/services/window_api.dart';
import 'package:pdm/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:pdm/shared/theme/app_theme.dart';

class PdmApp extends StatefulWidget {
  const PdmApp({super.key});

  @override
  State<PdmApp> createState() => _PdmAppState();
}

class _PdmAppState extends State<PdmApp> {
  bool _isMaximized = false;
  ListenerId? _windowListenerId;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // Same pattern as AppHeader: the window may not be discoverable
    // yet when this builds, so the listener is attached once it
    // exists. In a widget test there is no window, so the callback
    // simply never runs and the frame stays rounded.
    whenCurrentWindow((window) {
      if (_disposed) return;
      final isMaximized = window.isMaximized;
      _windowListenerId = window.addListener(_onWindowEvent);
      if (mounted && isMaximized != _isMaximized) {
        setState(() => _isMaximized = isMaximized);
      } else {
        _isMaximized = isMaximized;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final listenerId = _windowListenerId;
    if (listenerId != null) {
      currentWindow()?.removeListener(listenerId);
    }
    super.dispose();
  }

  // nativeapi reports a restore for both "no longer maximized" and
  // "no longer minimized", so the new state is read back from the
  // window rather than inferred from the event alone.
  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        final isMaximized = currentWindow()?.isMaximized ?? false;
        if (mounted && isMaximized != _isMaximized) {
          setState(() => _isMaximized = isMaximized);
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ponta Download Manager',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // FDM is a dark-only app: always use the dark (FDM) theme so the
      // UI matches the Free Download Manager screenshot, whatever the
      // OS theme is. AppTheme.light is kept in code if a light theme is
      // ever wanted back.
      themeMode: ThemeMode.dark,
      // Rounded window frame: the native window is undecorated
      // with a transparent background (see main.dart), so clipping
      // the home screen rounds the window's corners. A maximized
      // window goes square, like the runner's own background.
      home: ClipRRect(
        borderRadius: _isMaximized
            ? BorderRadius.zero
            : BorderRadius.circular(10),
        child: const DownloadsScreen(),
      ),
    );
  }
}
