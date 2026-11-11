import 'package:freezed_annotation/freezed_annotation.dart';

import 'file_conflict_policy.dart';

part 'create_download_request.freezed.dart';
part 'create_download_request.g.dart';

@freezed
abstract class CreateDownloadRequest with _$CreateDownloadRequest {
  const factory CreateDownloadRequest({
    required String url,
    required String destination,
    int? maxConnections,
    int? priority,
    FileConflictPolicy? conflictPolicy,
  }) = _CreateDownloadRequest;

  factory CreateDownloadRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateDownloadRequestFromJson(json);
}
