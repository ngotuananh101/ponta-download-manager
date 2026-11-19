import 'dart:async';

/// The native window operations a tray restore needs, behind one seam so the
/// sequence below can be driven by a fake window in a test.
abstract class TrayRestoreHost {
  bool get isMinimized;
  bool get isMaximized;
  bool get isFullScreen;
  double get width;
  double get height;
  void restore();
  void show();
  void focus();
  void setSize(double width, double height);
  void scheduleFrame();
  void scheduleForcedFrame();
}

/// Shows the window from the tray and makes its surface draw a real frame.
///
/// Why this is more than show() + focus():
///
///  * `show()` alone leaves a minimized window minimized, so a window the user
///    minimized rather than hid would stay out of sight. It is restored first.
///  * A hidden window's surface is gone on Wayland. Showing it without asking
///    for a frame leaves the runner's opaque background showing through the
///    transparent view until something else (a resize) forces one. A frame is
///    requested immediately.
///  * That immediate frame can still fire before the Wayland surface is
///    configured and be dropped, with nothing scheduling another. One forced
///    frame 250ms later lands after the surface exists.
///  * Recreating the surface itself needs a size-allocate, and with an
///    unchanged size none comes. A real 1px height change forces one; the
///    restore 50ms later puts the window back at its exact size. Height, not
///    width: a width change re-runs horizontal layout, and the app's sidebar
///    collapses below 960px.
class TrayRestore {
  TrayRestore(this._host, {this.log});

  final TrayRestoreHost _host;
  final void Function(String message)? log;

  /// How long to wait for the surface to exist before forcing a frame.
  static const forcedFrameDelay = Duration(milliseconds: 250);

  /// How long the 1px nudge stays applied before the size is restored.
  static const nudgeRestoreDelay = Duration(milliseconds: 50);

  Timer? _forcedFrameTimer;
  Timer? _nudgeRestoreTimer;
  (double width, double height)? _nudgeOriginalSize;

  /// Brings the window back and makes it actually paint.
  ///
  /// Safe to call again while a previous restore is still settling: the
  /// pending nudge is undone first so the size cannot drift.
  void showFromTray() {
    if (_host.isMinimized) _host.restore();
    _host.show();
    _host.focus();

    _host.scheduleFrame();
    log?.call('Tray restore: window shown, immediate frame requested');

    _forcedFrameTimer?.cancel();
    _forcedFrameTimer = Timer(forcedFrameDelay, () {
      _forcedFrameTimer = null;
      _host.scheduleForcedFrame();
      log?.call('Tray restore: forced frame requested after 250ms');
      _nudge();
    });
  }

  void _nudge() {
    if (_nudgeRestoreTimer != null) {
      // A previous nudge has not been restored yet (two restores
      // overlapping): undo it first so the size cannot drift.
      _nudgeRestoreTimer!.cancel();
      _nudgeRestoreTimer = null;
      final previous = _nudgeOriginalSize;
      _nudgeOriginalSize = null;
      if (previous != null) _applySize(previous);
    }
    if (_host.isMaximized) {
      log?.call('Tray restore: size nudge skipped (maximized)');
      return;
    }
    if (_host.isFullScreen) {
      log?.call('Tray restore: size nudge skipped (fullscreen)');
      return;
    }
    final width = _host.width;
    final height = _host.height;
    if (width <= 0 || height <= 0) {
      log?.call('Tray restore: size nudge skipped (size 0x0)');
      return;
    }
    _nudgeOriginalSize = (width, height);
    _host.setSize(width, height + 1);
    log?.call('Tray restore: size nudge requested ('
      '${width.toInt()}x${height.toInt()} -> '
      '${width.toInt()}x${height.toInt() + 1})');
    _nudgeRestoreTimer = Timer(nudgeRestoreDelay, () {
      _nudgeRestoreTimer = null;
      final original = _nudgeOriginalSize;
      _nudgeOriginalSize = null;
      if (original != null) {
        _applySize(original);
        log?.call('Tray restore: size nudge restored ('
          '${original.$1.toInt()}x${original.$2.toInt()})');
      }
    });
  }

  void _applySize((double width, double height) size) =>
      _host.setSize(size.$1, size.$2);

  /// Cancels pending timers and undoes an unfinished nudge, so quitting or
  /// disposing never leaves the window 1px taller.
  void dispose() {
    _forcedFrameTimer?.cancel();
    _forcedFrameTimer = null;
    _nudgeRestoreTimer?.cancel();
    _nudgeRestoreTimer = null;
    final original = _nudgeOriginalSize;
    _nudgeOriginalSize = null;
    if (original != null) _applySize(original);
  }
}
