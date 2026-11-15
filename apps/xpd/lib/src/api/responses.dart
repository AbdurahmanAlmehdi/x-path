import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';

/// The headers of every JSON answer: a browser must read it as JSON and
/// nothing else.
const _jsonHeaders = {
  'content-type': 'application/json',
  'x-content-type-options': 'nosniff',
};

/// A JSON response with [body] encoded as the body.
Response jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {..._jsonHeaders, ...headers},
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
  headers: {..._jsonHeaders, ...headers},
);

/// The header of an answer that carries a secret, or must not be kept for
/// another reason: no browser or proxy stores it.
const noStore = {'cache-control': 'no-store'};

/// `503 secrets_locked`: the engine cannot read its secrets (D-10).
Response secretsLockedResponse() => errorResponse(
  ApiErrorCode.secretsLocked,
  'The engine cannot read its secrets right now.',
  hint:
      'Unlock them in the XPath app on the engine machine, or start xpd '
      'with its key, then try again. See '
      'docs/guide/troubleshooting.md#secrets-are-locked.',
);
