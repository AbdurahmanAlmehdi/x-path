// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiError _$ApiErrorFromJson(Map<String, dynamic> json) => ApiError(
  code: $enumDecode(_$ApiErrorCodeEnumMap, json['code']),
  message: json['message'] as String,
);

Map<String, dynamic> _$ApiErrorToJson(ApiError instance) => <String, dynamic>{
  'code': _$ApiErrorCodeEnumMap[instance.code]!,
  'message': instance.message,
};

const _$ApiErrorCodeEnumMap = {
  ApiErrorCode.invalidRequest: 'invalid_request',
  ApiErrorCode.unauthorized: 'unauthorized',
  ApiErrorCode.notFound: 'not_found',
  ApiErrorCode.conflict: 'conflict',
  ApiErrorCode.resyncRequired: 'resync_required',
  ApiErrorCode.credentialRejected: 'credential_rejected',
  ApiErrorCode.upgradeRequired: 'upgrade_required',
  ApiErrorCode.internal: 'internal',
  ApiErrorCode.upstreamError: 'upstream_error',
  ApiErrorCode.secretsLocked: 'secrets_locked',
};

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    ErrorResponse(ApiError.fromJson(json['error'] as Map<String, dynamic>));

Map<String, dynamic> _$ErrorResponseToJson(ErrorResponse instance) =>
    <String, dynamic>{'error': instance.error.toJson()};
