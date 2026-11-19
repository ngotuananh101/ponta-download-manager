import 'package:flutter/foundation.dart';

/// Provenance compiled into the binary; never inferred from the running host.
class BuildInfo {
  const BuildInfo({
    this.isDevelopment = kDebugMode,
    this.commit = const String.fromEnvironment('PDM_BUILD_COMMIT'),
    this.buildTime = const String.fromEnvironment('PDM_BUILD_TIME'),
  });

  final bool isDevelopment;
  final String commit;
  final String buildTime;

  String get commitText => _display(commit);
  String get buildTimeText => _display(buildTime);

  String _display(String value) {
    if (isDevelopment) return 'Development mode';
    return value.trim().isEmpty ? 'Unavailable' : value;
  }
}
