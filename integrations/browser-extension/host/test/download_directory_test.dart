import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:download_platform/download_platform.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pdm_native_host/src/host_runner.dart';
import 'package:pdm_native_host/src/native_message_codec.dart';
import 'package:test/test.dart';

class MockIpcClient extends Mock implements IpcClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      CreateDownloadRequest(
        url: 'http://127.0.0.1:9/f.bin',
        destination: '/tmp/f.bin',
      ),
    );
  });

  test('a browser download is written under the OS Downloads folder',
      () async {
    // The regression: bin/native_host.dart built
    // p.join(USERPROFILE|HOME, 'Downloads') itself, so a Downloads folder
    // moved in Windows was ignored, and the old folder was recreated.
    final client = MockIpcClient();
    when(() => client.close()).thenAnswer((_) async {});
    when(() => client.createDownload(any())).thenAnswer(
      (_) async => const DownloadInfo(
        id: 'dl-1',
        url: 'http://127.0.0.1:9/f.bin',
        fileName: 'f.bin',
        status: DownloadStatus.queued,
        totalBytes: 1000,
      ),
    );

    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    final replies = <Map<String, Object?>>[];
    final replySub = NativeMessageCodec.decode(output.stream).listen(
      replies.add,
    );
    final run = runNativeHost(
      input: input.stream,
      output: output.sink,
      clientFactory: () async => client,
    );
    input.add(
      NativeMessageCodec.encode({
        'type': 'download.create',
        'id': 'r1',
        'url': 'http://127.0.0.1:9/f.bin',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await input.close();
    await run;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await replySub.cancel();
    await output.close();

    expect(replies.single['ok'], isTrue);
    final captured =
        verify(() => client.createDownload(captureAny())).captured.single
            as CreateDownloadRequest;
    expect(
      captured.destination,
      p.join(defaultDownloadDirectory(), 'f.bin'),
    );
    expect(
      Directory(defaultDownloadDirectory()).isAbsolute,
      isTrue,
      reason: 'a relative default would write next to the host binary',
    );
  });

  test('an explicit downloadDirectory overrides the OS folder', () async {
    final client = MockIpcClient();
    when(() => client.close()).thenAnswer((_) async {});
    when(() => client.createDownload(any())).thenAnswer(
      (_) async => const DownloadInfo(
        id: 'dl-1',
        url: 'http://127.0.0.1:9/f.bin',
        fileName: 'f.bin',
        status: DownloadStatus.queued,
        totalBytes: 1000,
      ),
    );

    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    // The sink must have a listener: a non-broadcast controller's
    // `close()` future never completes while the stream is unlistened.
    final replySub = NativeMessageCodec.decode(output.stream).listen((_) {});
    final run = runNativeHost(
      input: input.stream,
      output: output.sink,
      clientFactory: () async => client,
      downloadDirectory: '/tmp/dl',
    );
    input.add(
      NativeMessageCodec.encode({
        'type': 'download.create',
        'id': 'r1',
        'url': 'http://127.0.0.1:9/f.bin',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await input.close();
    await run;
    await replySub.cancel();
    await output.close();

    final captured =
        verify(() => client.createDownload(captureAny())).captured.single
            as CreateDownloadRequest;
    expect(captured.destination, '/tmp/dl/f.bin');
  });
}
