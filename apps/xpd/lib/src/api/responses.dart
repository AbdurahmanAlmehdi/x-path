import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';

/// A JSON response with [body] encoded as the body.
Response jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json', ...headers},
);

/// An error response: the status of [code] and the error envelope.
Response errorResponse(
  ApiErrorCode code,
  String message, {
  Map<String, String> headers = const {},
  List<WorkflowIssue>? issues,
  String? hint,
  Map<String, Object?>? details,
}) => Response(
  code.statusCode,
  body: jsonEncode(
    ErrorResponse.of(
      code,
      message,
      issues: issues,
      hint: hint,
      details: details,
    ).toJson(),
  ),
  headers: {'content-type': 'application/json', ...headers},
);

/// `503 secrets_locked`: the engine cannot read its secrets (D-10).
Response secretsLockedResponse() => errorResponse(
  ApiErrorCode.secretsLocked,
  'The engine cannot read its secrets right now.',
  hint:
      'Unlock them in the XPath app on the engine machine, or start xpd '
      'with its key, then try again. See '
      'docs/guide/troubleshooting.md#secrets-are-locked.',
);
