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
}) => Response(
  code.statusCode,
  body: jsonEncode(ErrorResponse.of(code, message).toJson()),
  headers: {'content-type': 'application/json', ...headers},
);
