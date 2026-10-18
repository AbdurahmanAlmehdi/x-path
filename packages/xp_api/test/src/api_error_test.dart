import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('ApiErrorCode', () {
    test('maps every code to its HTTP status', () {
      expect(
        {for (final c in ApiErrorCode.values) c: c.statusCode},
        {
          ApiErrorCode.invalidRequest: 400,
          ApiErrorCode.unauthorized: 401,
          ApiErrorCode.forbidden: 403,
          ApiErrorCode.notFound: 404,
          ApiErrorCode.conflict: 409,
          ApiErrorCode.credentialInUse: 409,
          ApiErrorCode.alreadyDecided: 409,
          ApiErrorCode.resyncRequired: 409,
          ApiErrorCode.credentialRejected: 422,
          ApiErrorCode.workflowInvalid: 422,
          ApiErrorCode.upgradeRequired: 426,
          ApiErrorCode.internal: 500,
          ApiErrorCode.upstreamError: 502,
          ApiErrorCode.secretsLocked: 503,
        },
      );
    });
  });

  group('ErrorResponse', () {
    test('serializes to the error envelope with snake_case codes', () {
      final response = ErrorResponse.of(ApiErrorCode.resyncRequired, 'Reload.');

      expect(response.toJson(), {
        'error': {'code': 'resync_required', 'message': 'Reload.'},
      });
    });

    test('round-trips through JSON', () {
      for (final code in ApiErrorCode.values) {
        final response = ErrorResponse.of(code, 'm');

        expect(ErrorResponse.fromJson(response.toJson()), response);
      }
    });

    test('compares by value', () {
      const a = ApiError(code: ApiErrorCode.notFound, message: 'x');

      expect(
        ErrorResponse.of(ApiErrorCode.notFound, 'x'),
        const ErrorResponse(a),
      );
      expect(
        ErrorResponse.of(ApiErrorCode.notFound, 'y'),
        isNot(const ErrorResponse(a)),
      );
    });
  });
}
