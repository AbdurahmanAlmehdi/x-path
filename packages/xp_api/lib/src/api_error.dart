// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'api_error.g.dart';

/// Machine-readable reason carried by every error response.
///
/// The JSON value is the snake_case name. Each code maps to one HTTP status.
enum ApiErrorCode {
  /// The request is malformed (for example a negative `after` cursor).
  @JsonValue('invalid_request')
  invalidRequest(400),

  /// The bearer token is missing, unknown or revoked.
  @JsonValue('unauthorized')
  unauthorized(401),

  /// No such route or resource.
  @JsonValue('not_found')
  notFound(404),

  /// The request clashes with what the engine holds, for example a project
  /// that was added already.
  @JsonValue('conflict')
  conflict(409),

  /// The requested event cursor is outside the resume window; the client
  /// must reload its state and reconnect without a cursor.
  @JsonValue('resync_required')
  resyncRequired(409),

  /// A credential was not stored because the store or tool it is for refused
  /// it, or it is not usable (malformed key, wrong prefix). The message says
  /// what to do.
  @JsonValue('credential_rejected')
  credentialRejected(422),

  /// A workflow document was not saved or dispatched because it has issues
  /// (`POST .../workflows/validate` lists them with their lines), or a
  /// dispatch asked for something the project cannot do. The message says
  /// what to fix.
  @JsonValue('workflow_invalid')
  workflowInvalid(422),

  /// The route only speaks WebSocket.
  @JsonValue('upgrade_required')
  upgradeRequired(426),

  /// Something went wrong in the engine.
  @JsonValue('internal')
  internal(500),

  /// A service the engine depends on, for example GitHub, refused the call or
  /// could not be reached.
  @JsonValue('upstream_error')
  upstreamError(502),

  /// The engine cannot read its secrets (D-10); try again once they are
  /// unlocked.
  @JsonValue('secrets_locked')
  secretsLocked(503);

  new(this.statusCode);

  /// The HTTP status code of a response with this code.
  final int statusCode;
}

/// The body of an error: a code and a human-readable message.
@JsonSerializable()
class ApiError extends Equatable {
  /// Creates an error.
  const new({required this.code, required this.message});

  /// Reads an error from its JSON form.
  factory ApiError.fromJson(Map<String, dynamic> json) =>
      _$ApiErrorFromJson(json);

  /// Machine-readable reason.
  final ApiErrorCode code;

  /// Human-readable explanation. Never contains secrets.
  final String message;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ApiErrorToJson(this);

  @override
  List<Object?> get props => [code, message];
}

/// The envelope of every non-2xx JSON response: `{"error": {...}}`.
@JsonSerializable(explicitToJson: true)
class ErrorResponse extends Equatable {
  /// Creates an envelope around [error].
  const new(this.error);

  /// Creates an envelope from a [code] and a [message].
  ErrorResponse.of(ApiErrorCode code, String message)
    : error = ApiError(code: code, message: message);

  /// Reads an envelope from its JSON form.
  factory ErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  /// The error.
  final ApiError error;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ErrorResponseToJson(this);

  @override
  List<Object?> get props => [error];
}
