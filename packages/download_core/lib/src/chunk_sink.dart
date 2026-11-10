/// Receives downloaded bytes at their file offsets. The writer
/// coordinator owns all writes (§6.2); a segment is complete only after
/// its bytes are written (§6.3).
abstract interface class ChunkSink {
  /// Writes [bytes] at [offset], overwriting any bytes already there.
  Future<void> write(int offset, List<int> bytes);

  /// Flushes pending writes. Called once when the download reaches a
  /// terminal state.
  Future<void> close();

  /// Destination path, when the sink writes to a file; null otherwise.
  /// Reported in the completed event.
  String? get filePath;
}
