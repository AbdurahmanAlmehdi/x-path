import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('each status has its type, code and a fix', () {
    final errors = <AppStoreConnectException, int>{
      const AscAuthException('a', code: 'NOT_AUTHORIZED'): 401,
      const AscForbiddenException('a', code: 'FORBIDDEN'): 403,
      const AscNotFoundException('a', code: 'NOT_FOUND'): 404,
      const AscConflictException('a', code: 'ENTITY_ERROR'): 409,
      const AscValidationException('a', code: 'ENTITY_ERROR'): 422,
      const AscRateLimitedException('a', code: 'RATE_LIMIT_EXCEEDED'): 429,
      const AscServerException(503, 'a', code: 'X'): 503,
    };

    for (final MapEntry(key: error, value: status) in errors.entries) {
      expect(error.statusCode, status);
      expect(error.message, 'a');
      expect(error.code, isNotNull);
      expect(error.fix, isNotEmpty);
    }
  });

  test('a rate limit says how long to wait', () {
    const error = AscRateLimitedException(
      'slow down',
      retryAfter: Duration(seconds: 30),
    );

    expect(error.retryAfter, const Duration(seconds: 30));
    expect(const AscRateLimitedException('x').retryAfter, isNull);
  });

  test('prints status and message', () {
    expect(
      const AscNotFoundException('No app').toString(),
      'AppStoreConnectException(404): No app',
    );
  });
}
