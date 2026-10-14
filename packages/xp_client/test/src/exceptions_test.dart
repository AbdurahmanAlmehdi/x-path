import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('reads the error envelope', () {
      final error = ApiException.fromResponse(
        403,
        '{"error": {"code": "forbidden", "message": "No."}}',
      );

      expect(error.statusCode, 403);
      expect(error.code, ApiErrorCode.forbidden);
      expect(error.message, 'No.');
      expect(error.approval, isNull);
      expect(error.toString(), 'ApiException(403 forbidden): No.');
    });

    test('a code it does not know is no envelope', () {
      final error = ApiException.fromResponse(
        400,
        '{"error": {"code": "from_the_future", "message": "No."}}',
      );

      expect(error.code, isNull);
      expect(error.message, 'The engine answered HTTP 400.');
    });

    test('an empty body gives the status', () {
      final error = ApiException.fromResponse(500, '');

      expect(error.statusCode, 500);
      expect(error.code, isNull);
    });
  });
}
