/// Configuration for the standalone download engine process.
class EngineConfig {
  const EngineConfig({
    this.downloadDirectory = 'downloads',
    this.maxConcurrentDownloads = 3,
    this.maxConnectionsPerDownload = 8,
  });

  final String downloadDirectory;
  final int maxConcurrentDownloads;
  final int maxConnectionsPerDownload;
}
