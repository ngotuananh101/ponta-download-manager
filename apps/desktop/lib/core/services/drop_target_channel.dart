import 'package:flutter/services.dart';

/// What a drop carried, as the native runner reports it.
///
/// A drag usually fills only one or two of the three fields:
///
/// * [uris] — links (`http://`, `https://`, …) the drag carried as
///   `text/uri-list` entries.
/// * [files] — absolute paths of dropped files and directories. A
///   `file://` URI on Linux lands here too, converted by the runner.
/// * [text] — the plain-text payload (`STRING` on Linux,
///   `CF_UNICODETEXT` on Windows). Browsers put the dragged link here.
class DropPayload {
  const DropPayload({this.uris = const [], this.files = const [], this.text});

  final List<String> uris;
  final List<String> files;
  final String? text;
}

/// One event from the native drop target.
sealed class DropEvent {
  const DropEvent();
}

/// A drag entered the window.
final class DropEnteredEvent extends DropEvent {
  const DropEnteredEvent();
}

/// A drag moved within the window.
final class DropMovedEvent extends DropEvent {
  const DropMovedEvent();
}

/// The drag left the window, or was cancelled, without dropping.
final class DropExitedEvent extends DropEvent {
  const DropExitedEvent();
}

/// Data was dropped on the window.
final class DropDroppedEvent extends DropEvent {
  const DropDroppedEvent(this.payload);

  final DropPayload payload;
}

/// The `pdm/drop_target` channel that the platform runners drive.
///
/// Both runners register a native drop target on the app window and
/// call the Dart handler from the GTK / OLE drag-and-drop callbacks
/// (see `linux/runner/my_application.cc` and
/// `windows/runner/drop_target.cpp`). They own the handler because
/// neither available plugin fits: `desktop_drop` pins `cross_file`
/// ^0.4.0, which `file_picker` 13 cannot share, and `nativeapi`'s drop
/// target discards non-file URIs on Linux, which is exactly the
/// "drag a link from the browser" case.
///
/// Events are window-wide: the app has one window, and all of it
/// accepts a drop.
class DropTargetChannel {
  DropTargetChannel._();

  static const MethodChannel _channel = MethodChannel('pdm/drop_target');

  /// Registers [onEvent] and returns a function that unregisters it.
  ///
  /// Without a runner (a widget test) nothing ever calls the handler,
  /// so subscribing is harmless there. Events the runner emits before
  /// the handler is installed are dropped by the engine, which is
  /// fine — there is nothing to drop onto yet.
  static void Function() listen(void Function(DropEvent event) onEvent) {
    Future<Object?> handler(MethodCall call) async {
      final event = _parse(call);
      if (event != null) onEvent(event);
      return null;
    }

    _channel.setMethodCallHandler(handler);
    return () => _channel.setMethodCallHandler(null);
  }

  static DropEvent? _parse(MethodCall call) {
    switch (call.method) {
      case 'entered':
        return const DropEnteredEvent();
      case 'moved':
        return const DropMovedEvent();
      case 'exited':
        return const DropExitedEvent();
      case 'dropped':
        final args = call.arguments;
        if (args is! Map) return const DropDroppedEvent(DropPayload());
        return DropDroppedEvent(
          DropPayload(
            uris: _strings(args['uris']),
            files: _strings(args['files']),
            text: args['text'] as String?,
          ),
        );
    }
    return null;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }
}
