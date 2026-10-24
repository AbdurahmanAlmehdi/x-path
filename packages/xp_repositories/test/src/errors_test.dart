import 'package:test/test.dart';
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
