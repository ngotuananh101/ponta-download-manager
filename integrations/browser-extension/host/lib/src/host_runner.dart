import 'dart:async';
import 'dart:io';

import 'package:download_ipc/download_ipc.dart';
import 'package:download_platform/download_platform.dart';

import 'app_launcher.dart';
import 'native_host.dart';

/// Runs the Native Messaging host over [input]/[output] until the browser
/// closes the port.
///
/// [downloadDirectory] defaults to [defaultDownloadDirectory] — the folder the
/// OS reports as the user's Downloads folder, which is what a moved Downloads
/// folder changes. [clientFactory] and [socketPath] are seams for tests and
/// for the launcher's `PDM_APP_PATH` path; the defaults connect to the running
/// app, launching it when it is not up.
Future<void> runNativeHost({
  required Stream<List<int>> input,
  required StreamSink<List<int>> output,
  Future<IpcClient> Function()? clientFactory,
  String? downloadDirectory,
  String? socketPath,
}) async {
  final socket = socketPath ?? defaultSocketPath();
  final host = NativeHost(
    clientFactory: clientFactory ??
        () async {
          return connectWithAutoLaunch(
            connect: () async {
              final token = await File('$socket.token').readAsString();
              return IpcClient.connect(
                channelFactory: () => connectIpcChannel(socketPath: socket),
                token: token,
              );
            },
            launcher: AppLauncher(socketPath: socket),
          );
        },
    downloadDirectory: downloadDirectory ?? defaultDownloadDirectory(),
  );
  await host.run(input, output);
}
