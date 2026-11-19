import 'dart:async';
import 'dart:io';

/// Starts an external tool for a bounded health check.
typedef ExternalToolProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Runs a health check while retaining ownership of its process. On timeout,
/// terminate and reap it before returning so it cannot keep a managed binary
/// open (notably on Windows).
Future<ProcessResult> runExternalToolProcess(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 10),
  ExternalToolProcessStarter? startProcess,
}) async {
  final starter = startProcess ?? Process.start;
  final stopwatch = Stopwatch()..start();
  final process = await starter(executable, arguments).timeout(timeout);
  final stdout = process.stdout.transform(const SystemEncoding().decoder).join();
  final stderr = process.stderr.transform(const SystemEncoding().decoder).join();
  try {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('Tool health check timed out');
    final exitCode = await process.exitCode.timeout(remaining);
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  } on TimeoutException {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await Future.wait([stdout, stderr]);
    throw TimeoutException('Tool health check timed out', timeout);
  }
}
