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

    test('reads the flavors that use a credential it did not delete', () {
      final error = ApiException.fromResponse(
        409,
        '{"error": {"code": "credential_in_use", "message": "Used."}, '
        '"usedBy": [{"projectId": "prj_1", "app": ".", "flavor": "prod", '
        '"status": "verified"}]}',
      );

      expect(error.isCredentialInUse, isTrue);
      expect(error.isForbidden, isFalse);
      expect(error.usedBy, const [
        CredentialUsage(
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          status: CredentialStatus.verified,
        ),
      ]);
      expect(
        ApiException.fromResponse(
          403,
          '{"error": {"code": "forbidden", "message": "No."}}',
        ).usedBy,
        isEmpty,
      );
    });

    test('reads the issues of a workflow document', () {
      final error = ApiException.fromResponse(
        422,
        '{"error": {"code": "workflow_invalid", "message": "Issues.", '
        '"issues": [{"line": 3, "column": 5, "message": "Unknown input.", '
        r'"hint": "Did you mean \"inputs.ids\"?"}]}}',
      );

      expect(error.issues, const [
        WorkflowIssue(
          line: 3,
          column: 5,
          message: 'Unknown input.',
          hint: 'Did you mean "inputs.ids"?',
        ),
      ]);
      expect(
        ApiException.fromResponse(
          403,
          '{"error": {"code": "forbidden", "message": "No."}}',
        ).issues,
        isEmpty,
      );
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
