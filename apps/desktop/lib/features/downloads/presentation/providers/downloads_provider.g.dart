// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'downloads_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Downloads)
final downloadsProvider = DownloadsProvider._();

final class DownloadsProvider
    extends $AsyncNotifierProvider<Downloads, List<Download>> {
  DownloadsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadsHash();

  @$internal
  @override
  Downloads create() => Downloads();
}

String _$downloadsHash() => r'd1140fd82f543692718f17748c94f3a7f8006a15';

abstract class _$Downloads extends $AsyncNotifier<List<Download>> {
  FutureOr<List<Download>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Download>>, List<Download>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Download>>, List<Download>>,
              AsyncValue<List<Download>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
