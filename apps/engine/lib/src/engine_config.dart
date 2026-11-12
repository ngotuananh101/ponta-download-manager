/// Configuration for the standalone download engine process.
class EngineConfig {
  const EngineConfig({
    this.downloadDirectory = 'downloads',
    this.maxConcurrentDownloads = 3,
    this.maxConnectionsPerDownload = 8,
    this.maxTotalConnections = 16,
  });

  final String downloadDirectory;
  final int maxConcurrentDownloads;
  final int maxConnectionsPerDownload;

  /// Maximum total connections across all running downloads
  /// (docs/architecture.md §5.6). Configurable later via Settings.
  final int maxTotalConnections;
}
