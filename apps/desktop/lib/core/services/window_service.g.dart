// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'window_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the window lifecycle and the system tray: closing the
/// window hides it to the tray (downloads keep running in this
/// process), and only Quit from the tray menu exits for real.
///
/// Ported from dev-stack's WindowService, adapted to PDM (static
/// menu, no autostart, the engine + IPC host are what stop on quit).

@ProviderFor(WindowService)
final windowServiceProvider = WindowServiceProvider._();

/// Owns the window lifecycle and the system tray: closing the
/// window hides it to the tray (downloads keep running in this
/// process), and only Quit from the tray menu exits for real.
///
/// Ported from dev-stack's WindowService, adapted to PDM (static
/// menu, no autostart, the engine + IPC host are what stop on quit).
final class WindowServiceProvider
    extends $AsyncNotifierProvider<WindowService, void> {
  /// Owns the window lifecycle and the system tray: closing the
  /// window hides it to the tray (downloads keep running in this
  /// process), and only Quit from the tray menu exits for real.
  ///
  /// Ported from dev-stack's WindowService, adapted to PDM (static
  /// menu, no autostart, the engine + IPC host are what stop on quit).
  WindowServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'windowServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$windowServiceHash();

  @$internal
  @override
  WindowService create() => WindowService();
}

String _$windowServiceHash() => r'a932c12bb4d3400fb4be579053113483a61ac520';

/// Owns the window lifecycle and the system tray: closing the
/// window hides it to the tray (downloads keep running in this
/// process), and only Quit from the tray menu exits for real.
///
/// Ported from dev-stack's WindowService, adapted to PDM (static
/// menu, no autostart, the engine + IPC host are what stop on quit).

abstract class _$WindowService extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
