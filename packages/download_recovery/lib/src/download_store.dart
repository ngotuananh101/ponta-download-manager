import 'dart:convert';

import 'package:download_api/download_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'download_record.dart';

/// Thin SQLite repository for downloads and their segments (§9).
/// The API is synchronous: SQLite writes are fast, and the callers
/// (event handlers, timers) run on the engine isolate.
class DownloadStore {
  DownloadStore._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON;');
    _migrate();
  }

  factory DownloadStore.open(String path) {
    return DownloadStore._(sqlite3.open(path));
  }

  factory DownloadStore.inMemory() {
    return DownloadStore._(sqlite3.openInMemory());
  }

  final Database _db;

  void _migrate() {
    final version = _db.userVersion;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS downloads (
          id TEXT PRIMARY KEY,
          url TEXT NOT NULL,
          final_url TEXT,
          destination_path TEXT NOT NULL,
          partial_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          directory TEXT NOT NULL,
          total_bytes INTEGER NOT NULL DEFAULT -1,
          downloaded_bytes INTEGER NOT NULL DEFAULT 0,
          etag TEXT,
          last_modified TEXT,
          supports_range INTEGER,
          status TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 0,
          max_connections INTEGER NOT NULL DEFAULT 4,
          error_code TEXT,
          error_message TEXT,
          mirrors TEXT,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS segments (
          download_id TEXT NOT NULL,
          segment_index INTEGER NOT NULL,
          start_byte INTEGER NOT NULL,
          end_byte INTEGER,
          written_bytes INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (download_id, segment_index),
          FOREIGN KEY (download_id) REFERENCES downloads(id)
            ON DELETE CASCADE
        );
      ''');
      _db.userVersion = 1;
    }
    // Only a database that already existed at v1 (created by the
    // old code, without the columns) needs the ALTER: a fresh
    // database just created the tables WITH them.
    if (version == 1) {
      _migrateV1ToV2();
    }
    // Both paths end at the same schema.
    _db.userVersion = 2;
  }

  /// Adds the v2 columns (mirrors and tags, stored as JSON text).
  /// Only the columns that are missing are added, and both ALTERs
  /// run in one transaction, so a half-finished earlier migration —
  /// one ALTER applied, the other not, version still 1 — completes
  /// instead of dying on a duplicate column name.
  void _migrateV1ToV2() {
    final columns = _db
        .select('PRAGMA table_info(downloads);')
        .map((row) => row['name'] as String)
        .toSet();
    _db.execute('BEGIN;');
    try {
      if (!columns.contains('mirrors')) {
        _db.execute('ALTER TABLE downloads ADD COLUMN mirrors TEXT;');
      }
      if (!columns.contains('tags')) {
        _db.execute('ALTER TABLE downloads ADD COLUMN tags TEXT;');
      }
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void upsertDownload(DownloadRecord record) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      '''
      INSERT INTO downloads (
        id, url, final_url, destination_path, partial_path, file_name,
        directory, total_bytes, downloaded_bytes, etag, last_modified,
        supports_range, status, priority, max_connections, error_code,
        error_message, mirrors, tags, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        final_url = excluded.final_url,
        destination_path = excluded.destination_path,
        partial_path = excluded.partial_path,
        file_name = excluded.file_name,
        directory = excluded.directory,
        total_bytes = excluded.total_bytes,
        downloaded_bytes = excluded.downloaded_bytes,
        etag = excluded.etag,
        last_modified = excluded.last_modified,
        supports_range = excluded.supports_range,
        status = excluded.status,
        priority = excluded.priority,
        max_connections = excluded.max_connections,
        error_code = excluded.error_code,
        error_message = excluded.error_message,
        mirrors = excluded.mirrors,
        tags = excluded.tags,
        updated_at = excluded.updated_at;
      ''',
      [
        record.id,
        record.url,
        record.finalUrl,
        record.destinationPath,
        record.partialPath,
        record.fileName,
        record.directory,
        record.totalBytes,
        record.downloadedBytes,
        record.eTag,
        record.lastModified,
        record.supportsRange == null
            ? null
            : (record.supportsRange! ? 1 : 0),
        record.status.name,
        record.priority,
        record.maxConnections,
        record.errorCode,
        record.errorMessage,
        jsonEncode(record.mirrors),
        jsonEncode(record.tags),
        record.createdAt.millisecondsSinceEpoch,
        now,
      ],
    );
  }

  DownloadRecord? getDownload(String id) {
    final rows = _db.select('SELECT * FROM downloads WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return null;
    }
    return _recordFromRow(rows.first);
  }

  List<DownloadRecord> listDownloads() {
    return _db
        .select('SELECT * FROM downloads ORDER BY created_at ASC')
        .map(_recordFromRow)
        .toList();
  }

  List<DownloadRecord> listNonTerminal() {
    return _db
        .select(
          'SELECT * FROM downloads WHERE status IN (?, ?, ?) '
          'ORDER BY created_at ASC',
          [
            DownloadStatus.queued.name,
            DownloadStatus.downloading.name,
            DownloadStatus.paused.name,
          ],
        )
        .map(_recordFromRow)
        .toList();
  }

  void deleteDownload(String id) {
    _db.execute('DELETE FROM downloads WHERE id = ?', [id]);
  }

  void saveCheckpoint(DownloadRecord record, List<SegmentRecord> segments) {
    _db.execute('BEGIN');
    try {
      upsertDownload(record);
      _db.execute('DELETE FROM segments WHERE download_id = ?', [record.id]);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final s in segments) {
        _db.execute(
          '''
          INSERT INTO segments (
            download_id, segment_index, start_byte, end_byte,
            written_bytes, status, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            s.downloadId,
            s.segmentId,
            s.start,
            s.end,
            s.downloaded,
            s.isComplete ? 'completed' : 'downloading',
            now,
          ],
        );
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<SegmentRecord> getSegments(String downloadId) {
    return _db
        .select(
          'SELECT * FROM segments WHERE download_id = ? '
          'ORDER BY segment_index ASC',
          [downloadId],
        )
        .map(
          (row) => SegmentRecord(
            downloadId: row['download_id'] as String,
            segmentId: row['segment_index'] as int,
            start: row['start_byte'] as int,
            end: row['end_byte'] as int?,
            downloaded: row['written_bytes'] as int,
          ),
        )
        .toList();
  }

  void close() => _db.dispose();

  static List<String> _stringList(String? json) {
    if (json == null || json.isEmpty) return const [];
    return (jsonDecode(json) as List).cast<String>();
  }

  DownloadRecord _recordFromRow(Row row) {
    return DownloadRecord(
      id: row['id'] as String,
      url: row['url'] as String,
      fileName: row['file_name'] as String,
      directory: row['directory'] as String,
      status: DownloadStatus.values.byName(row['status'] as String),
      downloadedBytes: row['downloaded_bytes'] as int,
      totalBytes: row['total_bytes'] as int,
      eTag: row['etag'] as String?,
      lastModified: row['last_modified'] as String?,
      finalUrl: row['final_url'] as String?,
      supportsRange: row['supports_range'] == null
          ? null
          : (row['supports_range'] as int) == 1,
      priority: row['priority'] as int,
      maxConnections: row['max_connections'] as int,
      errorCode: row['error_code'] as String?,
      errorMessage: row['error_message'] as String?,
      mirrors: _stringList(row['mirrors'] as String?),
      tags: _stringList(row['tags'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
      ),
    );
  }
}
