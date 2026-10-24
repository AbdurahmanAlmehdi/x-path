import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'helpers/helpers.dart';

void main() {
  test(
    'errorMessage gives the words of the engine or network, never raw ones',
    () {
      expect(errorMessage(notFound), 'No such thing.');
      expect(errorMessage(offline), 'Connection refused.');
      expect(errorMessage(StateError('bug')), unexpectedErrorMessage);
      expect(
        errorReason(
          const ApiException(
            'Archived.',
            statusCode: 409,
            details: {'reason': ErrorReason.archived},
          ),
        ),
        ErrorReason.archived,
      );
      expect(errorReason(const ApiException('No.', statusCode: 409)), isNull);
      expect(errorReason(StateError('bug')), isNull);
      expect(errorMessage(const FileSystemException('Busy')), 'Busy');
      expect(
        errorMessage(
          const FileSystemException(
            'Cannot open file',
            '/tmp/x.yaml',
            OSError('No such file or directory', 2),
          ),
        ),
        'Cannot open file: No such file or directory: /tmp/x.yaml',
      );
      expect(
        errorMessage(
          const ApiException(
            'Secrets are locked.',
            statusCode: 423,
            hint: 'Unlock the Keychain.',
          ),
        ),
        'Secrets are locked. Unlock the Keychain.',
      );
      expect(
        errorMessage(const ApprovalAlreadyDecided('Decided already.')),
        'Decided already.',
      );
      expect(errorMessage(const CredentialInUse('In use.')), 'In use.');
      expect('${const CredentialInUse('In use.')}', 'CredentialInUse: In use.');
    },
  );
}
