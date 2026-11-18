import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// window_manager 0.6 re-exports nativeapi's windowing API; the tray and window
// types here all come from nativeapi, so this file names its source directly
// instead of going through the re-export.
import 'package:nativeapi/nativeapi.dart';
// `ImageAsset.fromAsset` lives in `nativeapi_flutter` since nativeapi 0.4;
// the tray icon still resolves its image through it.
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show ImageAsset;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/downloads/domain/entities/download.dart';
import '../../features/downloads/providers/download_providers.dart';
import 'linux_desktop_service.dart';
import 'window_api.dart';

part 'window_service.g.dart';

final _log = Logger('WindowService');

/// Owns the window lifecycle and the system tray: closing the
/// window hides it to the tray (downloads keep running in this
/// process), and only Quit from the tray menu exits for real.
///
/// Ported from dev-stack's WindowService, adapted to PDM (static
/// menu, no autostart, the engine + IPC host are what stop on quit).
@Riverpod(keepAlive: true)
class WindowService extends _$WindowService {
  TrayIcon? _trayIcon;
  Image? _trayIconImage;
  ListenerId? _trayListenerId;
  _TrayMenu? _trayMenu;
  ListenerId? _windowListenerId;

  /// True while a quit this app started is closing the window, so the close
  /// listener lets the request through instead of hiding to the tray.
  bool _isQuitting = false;

  @override
  Future<void> build() async {
    // Close requests reach only the window's own listeners. Registering there
    // is how 0.6 replaces `setPreventClose(true)` + `onWindowClose`: the request
    // is deferred until this callback finishes, so a cancelled request keeps the
    // window open and an accepted one closes it.
    whenCurrentWindow((window) {
      _windowListenerId = window.addListener(_onWindowEvent);
    });

    ref.onDispose(() {
      final windowListenerId = _windowListenerId;
      if (windowListenerId != null) {
        currentWindow()?.removeListener(windowListenerId);
      }
      _windowListenerId = null;

      final listenerId = _trayListenerId;
      if (listenerId != null) {
        _trayIcon?.removeListener(listenerId);
      }
      _trayListenerId = null;

      _trayMenu?.dispose();
      _trayMenu = null;

      _trayIcon?.dispose();
      _trayIcon = null;
      _trayIconImage?.dispose();
      _trayIconImage = null;
    });

    _initSystemTray();
  }

  // --- Tray ---

  void _initSystemTray() {
    final iconPath = Platform.isWindows
        ? 'assets/images/icon.ico'
        : (Platform.isLinux
              ? LinuxDesktopService.resolveIconPath()
              : 'assets/images/icon.png');

    try {
      final icon = TrayIcon.create();
      if (icon == null) {
        _log.severe(
          'Tray initialization failed: TrayIcon.create() returned null',
        );
        return;
      }
      _trayIcon = icon;

      // ImageAsset.fromAsset resolves a bundled asset against
      // Platform.resolvedExecutable; Image.fromFile covers the absolute paths
      // the Linux resolver returns.
      final image = ImageAsset.fromAsset(iconPath) ?? Image.fromFile(iconPath);
      if (image != null) {
        icon.icon = image;
        // The wrapper owns the native handle and frees it when collected, so it
        // has to stay reachable for as long as the tray icon does.
        _trayIconImage = image;
      }

      if (Platform.isWindows) {
        icon.setTooltip('Ponta Download Manager');
      }

      // Linux renders the tray through StatusNotifierItem over D-Bus, where
      // there is no manual popup: OpenContextMenu() is a no-op returning false,
      // and the host only shows an exported menu when a trigger is set. The
      // native backend exposes the menu only for
      // ContextMenuTrigger.clicked; any other value leaves the menu empty,
      // so clicking the icon shows nothing. On GNOME's AppIndicator
      // extension a left click toggles that exported menu, so `clicked` is
      // what makes the menu appear.
      if (Platform.isLinux) {
        icon.setContextMenuTrigger(ContextMenuTrigger.clicked);
      }
      icon.setVisible(true);

      // nativeapi reports whole clicks.
      _trayListenerId = icon.addListener((event) {
        switch (event) {
          case TrayIconClickedEvent():
            Timer.run(_showWindow);
          case TrayIconRightClickedEvent():
            Timer.run(icon.openContextMenu);
          case TrayIconDoubleClickedEvent():
            break; // no-op
        }
      });

      final menu = _TrayMenu();
      menu.addAction('Show', _showWindow);
      menu.addSeparator();
      menu.addAction('Pause all', () => unawaited(pauseAll()));
      menu.addSeparator();
      menu.addAction('Quit', () => unawaited(quit()));
      _trayMenu = menu;
      icon.setContextMenu(menu.root);
    } catch (e) {
      _log.severe('Tray initialization failed: $e');
    }
  }

  /// Pauses every download that is currently downloading or queued.
  Future<void> pauseAll() async {
    final downloads = ref.read(downloadsProvider).value ?? const [];
    final repository = ref.read(downloadRepositoryProvider);
    for (final download in downloads) {
      if (download.state == DownloadState.downloading ||
          download.state == DownloadState.queued) {
        await repository.pauseDownload(download.id);
      }
    }
  }

  /// Quits for real: stops the engine + the IPC host, then closes
  /// the window. Called from the tray menu.
  Future<void> quit() async {
    _isQuitting = true;
    await _stopEngine();
    _closeWindow();
  }

  Future<void> _stopEngine() async {
    try {
      await ref.read(downloadDatasourceProvider).dispose();
    } catch (e) {
      _log.warning('Failed to dispose the engine on quit: $e');
    }
    try {
      await (await ref.read(engineIpcHostProvider.future)).close();
    } catch (e) {
      _log.warning('Failed to close the IPC host on quit: $e');
    }
  }

  /// Brings the window back from the tray.
  ///
  /// `show()` alone leaves a minimized window minimized, so a window the user
  /// minimized rather than hid would stay out of sight.
  void _showWindow() {
    final window = currentWindow();
    if (window == null) return;
    if (window.isMinimized) window.restore();
    window.show();
    window.focus();
  }

  /// Closes the window for good, past the tray.
  ///
  /// A close request the app starts itself still travels through the window's
  /// close listeners, so [_isQuitting] is what makes [_onWindowEvent] accept it.
  void _closeWindow() {
    _isQuitting = true;
    final window = currentWindow();
    if (window == null) {
      // No native window to close (nothing to put the request through); end the
      // process instead, which is what closing the last window does anyway.
      Application.instance.quit(0);
      return;
    }
    window.close();
  }

  /// Handles the window events this service cares about.
  ///
  /// The return type matters: nativeapi keeps a close request pending until the
  /// listener's future completes, and accepts it when it does. Returning
  /// [_handleCloseRequest] is therefore what defers the close until the
  /// decision is made.
  FutureOr<void> _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowCloseRequestedEvent():
        return _handleCloseRequest(event.request);
      default:
        break;
    }
  }

  /// Decides what the title bar's close button does.
  ///
  /// PDM always minimizes to the tray on close: the request is
  /// cancelled and the window is hidden. A close this app started
  /// itself (`_closeWindow`) is already the decision, so it is
  /// accepted by simply returning.
  Future<void> _handleCloseRequest(EventRequest request) async {
    if (_isQuitting) return;
    request.cancel();
    currentWindow()?.hide();
  }
}

/// Quits the app for real, through the [WindowService].
///
/// A plain provider (not generated) so widget tests can override it
/// with a recording stub: building the real service starts the tray,
/// which cannot run in a widget test.
final quitAppProvider = Provider<Future<void> Function()>(
  (ref) => () => ref.read(windowServiceProvider.notifier).quit(),
);

/// Owns every native wrapper created for one context menu.
///
/// `nativeapi` wrappers free their native handle when collected, and a listener
/// only outlives the wrapper it was registered on — so the menu, its items, and
/// their listener ids all have to stay reachable until the menu is replaced.
///
/// This mirrors the ownership pattern in `tray_manager`'s own `NativeMenuBinding`,
/// which is the reference implementation for wrapping this API. Two details from
/// it that matter here:
///
///  * `Menu.dispose()` does **not** free the items added to it, so items and
///    menus each need their own dispose pass. Skipping either leaks.
///  * Listeners are removed before anything is disposed, because a callback can
///    still fire while its item is alive.
///
/// The one deliberate difference: `NativeMenuBinding` keeps a single flat list
/// of menus and items across the whole tree, while this holder nests a child
/// `_TrayMenu` per submenu and disposes depth-first. Both free every wrapper
/// exactly once — the native handles are independent, so the order among them
/// does not matter — but nesting keeps each submenu's wrappers together, which
/// makes the structure easier to read than three parallel flat lists.
class _TrayMenu {
  _TrayMenu() {
    final menu = Menu.create();
    if (menu == null) {
      throw StateError('Unable to create the tray context menu');
    }
    root = menu;
    _menus.add(menu);
  }

  late final Menu root;

  final List<Menu> _menus = <Menu>[];
  final List<MenuItem> _items = <MenuItem>[];
  final List<_TrayMenu> _submenus = <_TrayMenu>[];
  final List<(MenuItem, ListenerId)> _listeners = <(MenuItem, ListenerId)>[];

  /// Adds a clickable row. The action is captured in the closure.
  MenuItem addAction(
    String label,
    void Function() action, {
    bool enabled = true,
  }) {
    final item = _newItem(label, MenuItemType.normal);
    item.isEnabled = enabled;
    _listeners.add((
      item,
      item.addListener((event) {
        if (event is MenuItemClickedEvent) {
          // `isolateLocal` runs this listener synchronously inside the native
          // trampoline, on the platform thread. The trampoline returns to
          // native the instant `action` suspends at its first `await`, and the
          // continuation is queued as a *microtask*. Flutter only drains that
          // queue after a task runs on the UI task runner (or after a frame),
          // so with nothing else scheduled the action simply stops — and while
          // the window is hidden there are no frames to flush it either. That
          // is why Quit did nothing until the window was shown again.
          //
          // Starting the work from the event loop instead makes the first
          // suspension happen inside a real task, so the microtask queue is
          // drained the moment that task returns.
          Timer.run(action);
        }
      }),
    ));
    root.addItem(item);
    return item;
  }

  /// A disabled row used as a heading.
  void addLabel(String label) {
    final item = _newItem(label, MenuItemType.normal);
    item.isEnabled = false;
    root.addItem(item);
  }

  void addSubmenu(String label, void Function(_TrayMenu submenu) build) {
    final item = _newItem(label, MenuItemType.submenu);
    final submenu = _TrayMenu();
    build(submenu);
    item.submenu = submenu.root;
    _submenus.add(submenu);
    root.addItem(item);
  }

  void addSeparator() => root.addSeparator();

  MenuItem _newItem(String label, MenuItemType type) {
    final item = MenuItem.createWithLabelAndType(label, type);
    if (item == null) {
      throw StateError('Unable to create the tray menu item "$label"');
    }
    _items.add(item);
    return item;
  }

  void dispose() {
    for (final (item, listenerId) in _listeners) {
      item.removeListener(listenerId);
    }
    _listeners.clear();
    // Children first: a submenu's items and menu are freed before the item that
    // owns them, and every wrapper is disposed exactly once.
    for (final submenu in _submenus) {
      submenu.dispose();
    }
    _submenus.clear();
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    for (final menu in _menus) {
      menu.dispose();
    }
    _menus.clear();
  }
}
