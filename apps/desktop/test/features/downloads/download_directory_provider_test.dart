import 'package:download_platform/download_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

void main() {
  test('the provider takes its value from the OS resolver', () {
    // The regression: the provider built the path itself with
    // p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads'),
    // so a Downloads folder moved in Windows was ignored and recreated.
    // A resolver returning a moved folder must reach the provider verbatim.
    final container = ProviderContainer.test(
      overrides: [
        downloadDirectoryResolverProvider.overrideWithValue(
          () => r'D:\Downloads moved',
        ),
      ],
    );
    expect(container.read(downloadDirectoryProvider), r'D:\Downloads moved');
  });

  test('the default resolver is the shared platform helper', () {
    final container = ProviderContainer.test();
    expect(
      container.read(downloadDirectoryProvider),
      defaultDownloadDirectory(),
    );
  });
}
