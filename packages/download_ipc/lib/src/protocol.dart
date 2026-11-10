import 'package:download_api/download_api.dart';

/// IPC protocol version. Every message carries it; a message with a
/// missing or unsupported version is rejected with
/// [IpcErrorCode.unsupportedVersion].
const int ipcProtocolVersion = 1;

/// Stable IPC error codes. A response carrying one of these is turned
/// into a [DownloadError] with the same code on the client.
abstract final class IpcErrorCode {
  static const String invalidMessage = 'invalid-message';
  static const String unsupportedVersion = 'unsupported-version';
  static const String unauthorized = 'unauthorized';
  static const String unknownMethod = 'unknown-method';
  static const String invalidParams = 'invalid-params';
  static const String notFound = 'not-found';
  static const String internal = 'internal';
  static const String timeout = 'timeout';
  static const String connectionClosed = 'connection-closed';
}

Map<String, Object?> downloadInfoToJson(DownloadInfo info) {
  return {
    'id': info.id,
    'url': info.url,
    'fileName': info.fileName,
    'status': info.status.name,
    'downloadedBytes': info.downloadedBytes,
    'totalBytes': info.totalBytes,
    'bytesPerSecond': info.bytesPerSecond,
  };
}

DownloadInfo downloadInfoFromJson(Map<String, Object?> json) {
  return DownloadInfo(
    id: json['id'] as String,
    url: json['url'] as String,
    fileName: json['fileName'] as String,
    status: DownloadStatus.values.byName(json['status'] as String),
    downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['totalBytes'] as num).toInt(),
    bytesPerSecond: (json['bytesPerSecond'] as num?)?.toInt() ?? 0,
  );
}

/// Encodes a [DownloadEvent] as an IPC event message
/// `{"type":"event","v":1,"event":<name>,"data":{...}}`.
Map<String, Object?> downloadEventToMessage(DownloadEvent event) {
  final (name, data) = event.when(
    progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) => (
      'download.progress',
      <String, Object?>{
        'downloadId': downloadId,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'bytesPerSecond': bytesPerSecond,
      },
    ),
    stateChanged: (downloadId, status) => (
      'download.stateChanged',
      <String, Object?>{
        'downloadId': downloadId,
        'status': status.name,
      },
    ),
    completed: (downloadId, filePath) => (
      'download.completed',
      <String, Object?>{
        'downloadId': downloadId,
        'filePath': filePath,
      },
    ),
    failed: (downloadId, code, message) => (
      'download.failed',
      <String, Object?>{
        'downloadId': downloadId,
        'code': code,
        'message': message,
      },
    ),
  );
  return {
    'type': 'event',
    'v': ipcProtocolVersion,
    'event': name,
    'data': data,
  };
}

/// Decodes an IPC event message's name + data into a [DownloadEvent],
/// or null when the name is unknown.
DownloadEvent? downloadEventFromMessage(
  String name,
  Map<String, Object?> data,
) {
  switch (name) {
    case 'download.progress':
      return DownloadEvent.progress(
        downloadId: data['downloadId'] as String,
        downloadedBytes: (data['downloadedBytes'] as num).toInt(),
        totalBytes: (data['totalBytes'] as num).toInt(),
        bytesPerSecond: (data['bytesPerSecond'] as num?)?.toInt() ?? 0,
      );
    case 'download.stateChanged':
      return DownloadEvent.stateChanged(
        downloadId: data['downloadId'] as String,
        status: DownloadStatus.values.byName(data['status'] as String),
      );
    case 'download.completed':
      return DownloadEvent.completed(
        downloadId: data['downloadId'] as String,
        filePath: data['filePath'] as String,
      );
    case 'download.failed':
      return DownloadEvent.failed(
        downloadId: data['downloadId'] as String,
        code: data['code'] as String,
        message: data['message'] as String,
      );
    default:
      return null;
  }
}

Map<String, Object?> ipcErrorMessage(String code, String message) {
  return {
    'type': 'error',
    'v': ipcProtocolVersion,
    'error': {'code': code, 'message': message},
  };
}

Map<String, Object?> ipcResponse(
  String id,
  Map<String, Object?> result,
) {
  return {
    'type': 'response',
    'v': ipcProtocolVersion,
    'id': id,
    'result': result,
  };
}

Map<String, Object?> ipcErrorResponse(
  String id,
  String code,
  String message,
) {
  return {
    'type': 'response',
    'v': ipcProtocolVersion,
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
