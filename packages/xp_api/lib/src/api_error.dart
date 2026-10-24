// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/workflow.dart';

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

  /// The bearer token is valid, but its kind may not do this (D-13): an MCP
  /// or runner token cannot approve, and only an app token loosens gates. The
  /// message names what the token's kind may do.
  @JsonValue('forbidden')
  forbidden(403),

  /// No such route or resource.
  @JsonValue('not_found')
  notFound(404),

  /// The request clashes with what the engine holds, for example a project
  /// that was added already.
  @JsonValue('conflict')
  conflict(409),

  /// The credential is used by flavors, so it is not deleted without
  /// `force`. The response lists them (`usedBy`).
  @JsonValue('credential_in_use')
  credentialInUse(409),

  /// The approval was decided already (first decision wins, D-13), or it
  /// expired. The response carries the approval as it stands.
  @JsonValue('already_decided')
  alreadyDecided(409),

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

  /// The code on the wire, such as `not_found`.
  String get wire => _$ApiErrorCodeEnumMap[this]!;
}

/// The `reason` in the `details` of an error, for the errors a client
/// answers differently: it suggests by reason, never by the message.
abstract final class ErrorReason {
  /// The workflow is archived; unarchiving it lets it run.
  static const archived = 'archived';

  /// Jobs ran the workflow, so it is kept: archive it instead.
  static const hasRuns = 'has_runs';

  /// A flavor has no credential of a kind its steps need.
  static const credentialUnassigned = 'credential_unassigned';

  /// No flavor is picked by default for the workflow; name the flavors.
  static const productionFlavor = 'production_flavor';

  /// The engine's copy of the repository has no such ref yet; a dispatch
  /// fetches before it looks again.
  static const refUnknown = 'ref_unknown';
}

/// The body of an error: a code, a human-readable message and, where it
/// helps, what to do.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ApiError extends Equatable {
  /// Creates an error.
  const new({
    required this.code,
    required this.message,
    this.issues,
    this.hint,
    this.details,
  });

  /// Reads an error from its JSON form.
  factory ApiError.fromJson(Map<String, dynamic> json) =>
      _$ApiErrorFromJson(json);

  /// Machine-readable reason.
  final ApiErrorCode code;

  /// Human-readable explanation. Never contains secrets.
  final String message;

  /// For `workflow_invalid`, the issues of the document, each at its line.
  final List<WorkflowIssue>? issues;

  /// What to do about it, in a sentence for the owner, for example "Unlock
  /// the secrets in the XPath app.". It names no command: a client adds its
  /// own.
  final String? hint;

  /// Facts of the error a client can act on, by name, for example the
  /// `kind` of a credential that is missing.
  final Map<String, Object?>? details;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ApiErrorToJson(this);

  @override
  List<Object?> get props => [code, message, issues, hint, details];
}

/// The envelope of every non-2xx JSON response: `{"error": {...}}`.
@JsonSerializable(explicitToJson: true)
class ErrorResponse extends Equatable {
  /// Creates an envelope around [error].
  const new(this.error);

  /// Creates an envelope from a [code], a [message] and the [issues] of a
  /// workflow document.
  ErrorResponse.of(
    ApiErrorCode code,
    String message, {
    List<WorkflowIssue>? issues,
    String? hint,
    Map<String, Object?>? details,
  }) : error = ApiError(
         code: code,
         message: message,
         issues: issues,
         hint: hint,
         details: details,
       );

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
