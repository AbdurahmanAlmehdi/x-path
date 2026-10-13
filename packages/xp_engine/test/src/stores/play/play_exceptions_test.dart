import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('each failure has its status, its message and a fix', () {
    final errors = <PlayException, int>{
      const PlayAuthException('a', reason: 'invalid_grant'): 401,
      const PlayForbiddenException('a'): 403,
      const PlayNotFoundException('a'): 404,
      const PlayReviewInProgressException(
        'a',
        reason: 'CHANGES_ALREADY_IN_REVIEW',
      ): 400,
      const PlayVersionCodeUsedException(403, 'a'): 403,
      const PlayConflictException('a'): 409,
      const PlayValidationException(400, 'a'): 400,
      const PlayRateLimitedException('a'): 429,
      const PlayServerException(503, 'a'): 503,
    };

    for (final MapEntry(key: error, value: status) in errors.entries) {
      expect(error.statusCode, status);
      expect(error.message, 'a');
      expect(error.fix, isNotEmpty);
    }
  });

  test('a rate limit says how long to wait', () {
    expect(
      const PlayRateLimitedException(
        'slow',
        retryAfter: Duration(seconds: 5),
      ).retryAfter,
      const Duration(seconds: 5),
    );
    expect(const PlayRateLimitedException('slow').retryAfter, isNull);
  });

  test('prints status and message', () {
    expect(
      const PlayNotFoundException('No app').toString(),
      'PlayException(404): No app',
    );
  });
}
