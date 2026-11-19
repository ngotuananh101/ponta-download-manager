import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/window_restore.dart';

/// A fake window that records every call the restore makes, so the test can
/// assert the order and the sizes instead of the native side.
class FakeWindow implements TrayRestoreHost {
  FakeWindow({this.width = 950, this.height = 650});

  @override
  double width;
  @override
  double height;
  final List<String> calls = <String>[];

  @override
  bool isMinimized = false;
  @override
  bool isMaximized = false;
  @override
  bool isFullScreen = false;

  @override
  void restore() => calls.add('restore');
  @override
  void show() => calls.add('show');
  @override
  void focus() => calls.add('focus');
  @override
  void scheduleFrame() => calls.add('scheduleFrame');
  @override
  void scheduleForcedFrame() => calls.add('scheduleForcedFrame');
  @override
  void setSize(double nextWidth, double nextHeight) {
    width = nextWidth;
    height = nextHeight;
    calls.add('setSize ${nextWidth.toInt()}x${nextHeight.toInt()}');
  }

  String get size => '${width.toInt()}x${height.toInt()}';
}

void main() {
  test('shows, focuses and reveals a minimized window in order', () {
    fakeAsync((async) {
      final window = FakeWindow()..isMinimized = true;
      final restore = TrayRestore(window);

      restore.showFromTray();

      expect(window.calls.take(4).toList(),
        ['restore', 'show', 'focus', 'scheduleFrame']);
      restore.dispose();
    });
  });

  test('leaves a hidden but unminimized window alone before showing it', () {
    fakeAsync((async) {
      final window = FakeWindow();
      final restore = TrayRestore(window);

      restore.showFromTray();

      expect(window.calls, isNot(contains('restore')));
      expect(window.calls.take(3).toList(), ['show', 'focus', 'scheduleFrame']);
      restore.dispose();
    });
  });

  test('forces a frame after the surface exists and nudges the size once', () {
    fakeAsync((async) {
      final window = FakeWindow();
      final restore = TrayRestore(window);

      restore.showFromTray();

      // Nothing forced right away: the frame would land before the surface is
      // configured and be dropped.
      expect(window.calls, isNot(contains('scheduleForcedFrame')));
      async.elapse(const Duration(milliseconds: 249));
      expect(window.calls, isNot(contains('scheduleForcedFrame')));

      async.elapse(const Duration(milliseconds: 1));
      expect(window.calls, contains('scheduleForcedFrame'));
      // +1px only: a real size change forces the size-allocate that recreates
      // the surface; width is untouched so nothing re-lays out horizontally.
      expect(window.size, '950x651');

      async.elapse(const Duration(milliseconds: 50));
      expect(window.size, '950x650');
      restore.dispose();
    });
  });

  test('skips the nudge for a maximized, fullscreen or zero-size window', () {
    for (final window in [
      FakeWindow()..isMaximized = true,
      FakeWindow()..isFullScreen = true,
      FakeWindow(width: 0, height: 0),
    ]) {
      fakeAsync((async) {
        final restore = TrayRestore(window);
        restore.showFromTray();
        async.elapse(const Duration(seconds: 1));
        expect(window.calls.where((c) => c.startsWith('setSize')), isEmpty);
        expect(window.calls, contains('scheduleForcedFrame'));
        restore.dispose();
      });
    }
  });

  test('a restore during a pending nudge undoes it before nudging again', () {
    fakeAsync((async) {
      final window = FakeWindow();
      final restore = TrayRestore(window);

      restore.showFromTray();
      async.elapse(const Duration(milliseconds: 260));
      expect(window.size, '950x651');

      // Second restore while the first nudge has not been undone yet: the
      // window must not drift to 652.
      restore.showFromTray();
      async.elapse(const Duration(milliseconds: 260));
      expect(window.size, '950x651');

      async.elapse(const Duration(milliseconds: 50));
      expect(window.size, '950x650');
      restore.dispose();
    });
  });

  test('dispose cancels pending timers and restores the real size', () {
    fakeAsync((async) {
      final window = FakeWindow();
      final restore = TrayRestore(window);

      restore.showFromTray();
      async.elapse(const Duration(milliseconds: 260));
      expect(window.size, '950x651');

      restore.dispose();
      expect(window.size, '950x650');

      final calls = List<String>.of(window.calls);
      async.elapse(const Duration(seconds: 2));
      expect(window.calls, calls);
    });
  });
}
