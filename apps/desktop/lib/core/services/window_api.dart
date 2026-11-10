import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Resolves the window this app owns, or null when there is none to have yet.
///
/// window_manager 0.6 addresses windows through nativeapi's FFI bindings
/// instead of a platform channel, so looking one up calls into the native
/// library. A widget test runs in a Dart VM that has no such library and the
/// lookup throws [ArgumentError]; null keeps callers on the degraded path they
/// take outside a real app, which is what the 0.5.x channel did by answering
/// nothing.
///
/// The answer can legitimately be null early in startup on Windows: the lookup
/// there is `GetActiveWindow()`, and the runner creates its window hidden and
/// only shows it on the first Flutter frame. Code that has to act on the window
/// should use [whenCurrentWindow] instead of deciding from a single lookup.
Window? currentWindow() => _currentWindow() ?? _adoptedWindow;

/// The window adopted from nativeapi's own `WindowCreatedEvent`.
Window? _adoptedWindow;

/// The manager-level listener installed while waiting for that event.
ListenerId? _adoptionListenerId;

/// Callbacks waiting for a window to exist.
final List<void Function(Window window)> _waitingForWindow =
    <void Function(Window window)>[];

/// Runs [callback] against this app's window — now if it is already known, as
/// soon as nativeapi reports it otherwise.
///
/// This is what makes the window handling work on Windows, where the window is
/// not discoverable from Dart at all: `WindowManager.getCurrent()` there is
/// `GetActiveWindow()`, which answers for the calling thread's message queue,
/// and the UI isolate has no window in its queue. The runner also creates its
/// window hidden and only shows it on the first Flutter frame, which is the
/// moment nativeapi turns into `WindowCreatedEvent`. The callback runs at most
/// once.
void whenCurrentWindow(void Function(Window window) callback) {
  final window = currentWindow();
  if (window != null) {
    callback(window);
    return;
  }
  _waitingForWindow.add(callback);
  _watchForCreatedWindow();

  // The listener is installed before this second look, so a window that became
  // discoverable in between is caught here rather than in an event that was
  // already delivered. `WindowManager.getAll()` is deliberately not used for
  // it: on Windows it enumerates every process's top-level windows, not just
  // this one's.
  final late = currentWindow();
  if (late != null) _adopt(late);
}

/// Installs the listener that adopts the window when nativeapi reports it.
///
/// This relies on being called before the window is shown: nativeapi starts
/// observing when the first listener is added, and it reports only windows
/// that appear afterwards — a window it finds already on screen is seeded
/// silently, without a `WindowCreatedEvent`. Every caller here runs from
/// `main()` or from the first build, which is before the runner shows the
/// window, so the event does arrive. A widget test has no window to show at
/// all, which is why the listener is simply left installed there.
void _watchForCreatedWindow() {
  if (_adoptionListenerId != null) return;
  try {
    _adoptionListenerId = WindowManager.instance.addListener(_onAnyWindowEvent);
  } on ArgumentError {
    // The native library could not be resolved, so there is nothing to listen
    // to and no window can ever appear. A widget test takes the resolved-window
    // path instead, through the resolver below.
  }
}

FutureOr<void> _onAnyWindowEvent(WindowEvent event) {
  if (event is WindowCreatedEvent) {
    _adoptWindow(event.windowId);
  }
}

void _adoptWindow(WindowId windowId) {
  if (_adoptedWindow != null) return;

  final Window? window;
  try {
    window = WindowManager.instance.get(windowId);
  } on ArgumentError {
    return;
  }
  if (window == null) return;
  _adopt(window);
}

void _adopt(Window window) {
  if (_adoptedWindow != null) return;
  _adoptedWindow = window;

  // The callbacks run before the adoption listener is removed, and that order
  // matters: they attach the first listeners to the window itself, which is
  // what makes nativeapi keep observing this process's windows. Removing the
  // last manager-level listener first would stop the observation and start it
  // again a moment later, needlessly.
  final waiting = List<void Function(Window window)>.of(_waitingForWindow);
  _waitingForWindow.clear();
  for (final callback in waiting) {
    callback(window);
  }

  // The listener did its job. Removing it keeps events for windows this app
  // does not own — a tray host window, a dialog — from being routed here.
  final listenerId = _adoptionListenerId;
  _adoptionListenerId = null;
  if (listenerId != null) {
    try {
      WindowManager.instance.removeListener(listenerId);
    } on ArgumentError {
      // Already gone with the library.
    }
  }
}

/// The lookup [currentWindow] delegates to.
///
/// `WindowManager.instance` is a const singleton backed by the native library,
/// so a test cannot substitute it; swapping the function is how a test hands
/// the widgets a fake window instead.
Window? Function() _currentWindow = _resolveNativeWindow;

Window? _resolveNativeWindow() {
  try {
    return WindowManager.instance.getCurrent();
  } on ArgumentError {
    return null;
  }
}

/// Points [currentWindow] at [resolver] until it is reset, and returns the
/// previous resolver so a test can restore it in `tearDown`.
///
/// The adopted window, any waiting callbacks and the adoption listener are
/// cleared too, so one test's fake window — or a wait a previous test left
/// behind — cannot leak into the next.
///
/// Only for widget tests: nothing in the app calls this.
@visibleForTesting
Window? Function() debugSetCurrentWindowResolver(Window? Function() resolver) {
  final previous = _currentWindow;
  _currentWindow = resolver;
  _adoptedWindow = null;
  _waitingForWindow.clear();

  final listenerId = _adoptionListenerId;
  _adoptionListenerId = null;
  if (listenerId != null) {
    try {
      WindowManager.instance.removeListener(listenerId);
    } on ArgumentError {
      // No native library in this test process.
    }
  }
  return previous;
}
