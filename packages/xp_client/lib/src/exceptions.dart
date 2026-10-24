import 'dart:convert';

import 'package:xp_api/xp_api.dart';

/// Something went wrong talking to the engine. Every error `XpClient` throws
/// is one of its subclasses.
sealed class XpClientException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong, in words a person can read. Never contains a token.
  final String message;
}

/// The engine answered, and the answer was an error: the error envelope
/// (`{"error": {"code": ..., "message": ...}}`) of a non-2xx response.
final class ApiException extends XpClientException {
  /// Creates an exception for a response with [statusCode].
  const new(
    super.message, {
    required this.statusCode,
    this.code,
    this.approval,
    this.usedBy = const [],
    this.issues = const [],
  });

  /// Reads the error out of the [body] of a response with [statusCode].
  ///
  /// A body that is not the error envelope (a proxy's HTML page, an empty
  /// body) still gives an exception: it has the status and no [code].
  factory fromResponse(int statusCode, String body) {
    try {
      final json = jsonDecode(body);
      final envelope = ErrorResponse.fromJson(json as Map<String, dynamic>);
      final approval = json['approval'];
      final usedBy = json['usedBy'];
      return ApiException(
        envelope.error.message,
        statusCode: statusCode,
        code: envelope.error.code,
        approval: approval is Map<String, dynamic>
            ? Approval.fromJson(approval)
            : null,
        usedBy: usedBy is List<dynamic>
            ? [
                for (final usage in usedBy)
                  CredentialUsage.fromJson(usage as Map<String, dynamic>),
              ]
            : const [],
        issues: envelope.error.issues ?? const [],
      );
    } on Object {
      return ApiException(
        'The engine answered HTTP $statusCode.',
        statusCode: statusCode,
      );
    }
  }

  /// The HTTP status.
  final int statusCode;

  /// The machine-readable reason, or `null` if the engine's answer was not
  /// the error envelope.
  final ApiErrorCode? code;

  /// The approval as it stands, when the error is
  /// [ApiErrorCode.alreadyDecided].
  final Approval? approval;

  /// The flavors that use the credential, when the error is
  /// [ApiErrorCode.credentialInUse].
  final List<CredentialUsage> usedBy;

  /// The issues of the workflow document, each at its line, when the error
  /// is [ApiErrorCode.workflowInvalid] about a document.
  final List<WorkflowIssue> issues;

  /// Whether the credential was not deleted because flavors use it.
  bool get isCredentialInUse => code == ApiErrorCode.credentialInUse;

  /// Whether the token is missing, unknown or revoked.
  bool get isUnauthorized => code == ApiErrorCode.unauthorized;

  /// Whether the token's kind may not do this (D-13).
  bool get isForbidden => code == ApiErrorCode.forbidden;

  /// Whether the event or log cursor is outside what the engine keeps.
  bool get isResyncRequired => code == ApiErrorCode.resyncRequired;

  @override
  String toString() => 'ApiException($statusCode ${code?.name}): $message';
}

/// The engine could not be reached, or the connection broke: the network, a
/// wrong URL, a stopped engine, a timeout.
final class ConnectionException extends XpClientException {
  /// Creates an exception with [message] and the [cause] that is behind it.
  const new(super.message, {this.cause});

  /// The error that was caught, for diagnostics.
  final Object? cause;

  @override
  String toString() => 'ConnectionException: $message';
}

/// A downloaded file is not what the engine said it is.
final class DownloadException extends XpClientException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'DownloadException: $message';
}
