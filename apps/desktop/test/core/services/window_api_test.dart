import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/window_api.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `borrowed` keeps the handle from being freed on collection; nothing here
  // calls into the native library through it.
  final window = Window.borrowed(0);

  late Window? Function() previousResolver;

  tearDown(() {
    debugSetCurrentWindowResolver(previousResolver);
  });

  test('adopts the hidden runner window before any show event', () async {
    previousResolver = debugSetCurrentWindowResolver(() => null);
    final seen = <Window>[];
    whenCurrentWindow(seen.add);
    await initializeRunnerWindow(
      readHandle: () async => 123,
      wrapHandle: (handle) {
        expect(handle, 123);
        return window;
      },
    );
    expect(currentWindow(), same(window));
    expect(seen, [same(window)]);
  });

  test('a missing runner handle reports startup failure instead of waiting forever', () async {
    previousResolver = debugSetCurrentWindowResolver(() => null);
    await expectLater(initializeRunnerWindow(readHandle: () async => null), throwsStateError);
  });

  test('runs the callback at once when the window is already known', () {
    previousResolver = debugSetCurrentWindowResolver(() => window);

    final seen = <Window>[];
    whenCurrentWindow(seen.add);

    expect(seen, [same(window)]);
  });

  test('defers the callback until the window can be found', () {
    // The Windows startup case: the first lookup answers nothing, the second
    // one — after the adoption listener is installed — finds the window.
    var lookups = 0;
    previousResolver = debugSetCurrentWindowResolver(() {
      lookups++;
      return lookups == 1 ? null : window;
    });

    final seen = <Window>[];
    whenCurrentWindow(seen.add);

    expect(lookups, greaterThanOrEqualTo(2));
    expect(seen, [same(window)]);
  });

  test('keeps waiting instead of failing when no window is ever found', () {
    previousResolver = debugSetCurrentWindowResolver(() => null);

    final seen = <Window>[];
    whenCurrentWindow(seen.add);

    expect(seen, isEmpty);
    expect(currentWindow(), isNull);
  });

  test('runs each waiting callback once, in registration order', () {
    var lookups = 0;
    previousResolver = debugSetCurrentWindowResolver(() {
      lookups++;
      // Only the "late" look below sees the window.
      return lookups == 1 ? null : window;
    });

    final order = <String>[];
    whenCurrentWindow((_) => order.add('first'));
    whenCurrentWindow((_) => order.add('second'));

    // The first call already adopted the window, so the second ran at once.
    expect(order, ['first', 'second']);

    // Registering again after adoption runs the new callback immediately.
    whenCurrentWindow((_) => order.add('third'));
    expect(order, ['first', 'second', 'third']);
  });

  test('keeps the window it found once the lookup stops answering', () {
    // What Windows does once the window is hidden: `GetActiveWindow()` is the
    // lookup there, and a hidden window is no longer the active one, so it
    // answers nothing. The window the app found at startup must still be it.
    var lookups = 0;
    previousResolver = debugSetCurrentWindowResolver(
      () => lookups++ == 0 ? window : null,
    );

    whenCurrentWindow((_) {});

    expect(currentWindow(), same(window));
  });

  test('does not switch to another window the lookup reports later', () {
    // A native context menu makes its own message-only host window the active
    // one (`Menu::Open()` calls `SetForegroundWindow(host_window)`), so the
    // lookup starts answering with that window — one that can never be shown.
    final menuHostWindow = Window.borrowed(1);
    var lookups = 0;
    previousResolver = debugSetCurrentWindowResolver(
      () => lookups++ == 0 ? window : menuHostWindow,
    );

    whenCurrentWindow((_) {});

    expect(currentWindow(), same(window));
  });

  test('a wait left by one test does not leak into the next', () {
    previousResolver = debugSetCurrentWindowResolver(() => null);

    final seen = <Window>[];
    whenCurrentWindow(seen.add);
    expect(seen, isEmpty);

    // Starting over drops the pending callback, as tearDown does between tests.
    debugSetCurrentWindowResolver(() => window);

    whenCurrentWindow(seen.add);
    expect(seen, [same(window)]);
  });
}
