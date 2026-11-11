/// What to do when the destination file already exists when a
/// download is created. Null (absent) means "ask": the engine throws
/// `file-exists` and the caller decides.
enum FileConflictPolicy {
  /// Replace the existing file when the download finishes.
  overwrite,

  /// Save under the first free name: `file (1).ext`, `file (2).ext`, ...
  rename,
}
