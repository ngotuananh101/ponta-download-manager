import 'dart:async';

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
      // A moved Downloads folder: the resolver answers this path, so the
      // destination must follow it rather than re-derive %USERPROFILE%.
      // Comparing against defaultDownloadDirectory() would be tautological —
      // on this Linux host the pre-fix inline expression returns exactly the
      // same path, so such a test could not fail (verified by reverting the
      // implementation to it: the test still passed).
      // The space and non-ASCII characters pin that the path survives intact.
      // A POSIX shape is used because NativeHost joins with the host's path
      // context; on Windows that context is windows, so the production shape
      // is joined correctly there.
      downloadDirectoryResolver: () => '/mnt/Ổ D/Tải xuống',
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
    // Joined with the host's own path context: NativeHost uses p.join, so the
    // separator must follow the platform this test runs on.
    expect(captured.destination, p.join('/mnt/Ổ D/Tải xuống', 'f.bin'));
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
    expect(captured.destination, p.join('/tmp/dl', 'f.bin'));
  });

  test('with neither seam set, the host asks the shared platform helper',
      () async {
    // Pins the wiring the other two tests bypass: no downloadDirectory, no
    // resolver — the destination must still be an absolute path under the
    // OS-reported Downloads folder, not a relative one beside the binary.
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
    final replySub = NativeMessageCodec.decode(output.stream).listen((_) {});
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
    await replySub.cancel();
    await output.close();

    final captured =
        verify(() => client.createDownload(captureAny())).captured.single
            as CreateDownloadRequest;
    final resolved = defaultDownloadDirectory();
    // The comment above says "absolute", so assert it: a relative resolved
    // path would put downloads next to the host binary. Joining with the
    // host's context matches what NativeHost does.
    expect(p.isAbsolute(resolved), isTrue);
    expect(captured.destination, p.join(resolved, 'f.bin'));
  });
}
