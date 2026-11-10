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
