import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:shelf/shelf.dart';

/// The request cannot be read: the body is not JSON, or not of the right
/// shape. Becomes `400 invalid_request`.
class BadRequestException implements Exception {
  /// Creates the exception with a [message] for the client.
  const new(this.message);

  /// What is wrong with the request.
  final String message;
}

/// The JSON object in the body of [request], read with [fromJson].
///
/// Throws a [BadRequestException] if the body is not a JSON object of the
/// right shape.
Future<T> readJsonBody<T>(
  Request request,
  T Function(Map<String, dynamic> json) fromJson,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException {
    throw const BadRequestException('The body is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const BadRequestException('The body must be a JSON object.');
  }
  try {
    return fromJson(decoded);
  } on CheckedFromJsonException catch (error) {
    throw BadRequestException(
      'The body has a field that is missing or of the wrong type'
      '${error.key == null ? '' : ': ${error.key}'}.',
    );
  }
}
