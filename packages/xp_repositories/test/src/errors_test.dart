import 'package:test/test.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'helpers/helpers.dart';

void main() {
  test('errorMessage gives the words of the engine or the network', () {
    expect(errorMessage(notFound), 'No such thing.');
    expect(errorMessage(offline), 'Connection refused.');
    expect(errorMessage(StateError('bug')), 'Bad state: bug');
    expect(
      errorMessage(const ApprovalAlreadyDecided('Decided already.')),
      'Decided already.',
    );
    expect(errorMessage(const CredentialInUse('In use.')), 'In use.');
    expect('${const CredentialInUse('In use.')}', 'CredentialInUse: In use.');
    const ssh = SshUrlRequired('Use SSH.', sshUrl: 'git@h:a.git');
    expect(errorMessage(ssh), 'Use SSH.');
    expect('$ssh', 'SshUrlRequired: Use SSH.');
  });
}
