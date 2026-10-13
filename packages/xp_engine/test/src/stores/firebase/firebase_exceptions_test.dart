import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('every failure has a status, a message and a fix', () {
    final errors = <FirebaseException>[
      const FirebaseAuthException('m', reason: 'invalid_grant'),
      const FirebaseForbiddenException('m'),
      const FirebaseNotFoundException('m'),
      const FirebaseValidationException(400, 'm'),
      const FirebaseRateLimitedException('m', retryAfter: Duration(seconds: 5)),
      const FirebaseServerException(503, 'm'),
      const FirebaseOperationFailedException('m'),
    ];

    expect(
      [for (final error in errors) error.statusCode],
      [401, 403, 404, 400, 429, 503, 0],
    );
    for (final error in errors) {
      expect(error.message, 'm');
      expect(error.fix, isNotEmpty);
      expect(error.toString(), contains('m'));
    }
    expect(errors.first.reason, 'invalid_grant');
    expect((errors[4] as FirebaseRateLimitedException).retryAfter, isNotNull);
  });
}
