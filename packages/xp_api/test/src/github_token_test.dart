import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('GitHubTokenStatus', () {
    test('without a token is only "stored": false', () {
      expect(const GitHubTokenStatus(stored: false).toJson(), {
        'stored': false,
      });
    });

    test('round-trips a checked token through JSON', () {
      const status = GitHubTokenStatus(
        stored: true,
        status: CredentialStatus.rejected,
        login: 'octocat',
        message: 'GitHub refused the token.',
        fix: 'Save a new token.',
      );

      expect(status.toJson(), {
        'stored': true,
        'status': 'rejected',
        'login': 'octocat',
        'message': 'GitHub refused the token.',
        'fix': 'Save a new token.',
      });
      expect(GitHubTokenStatus.fromJson(status.toJson()), status);
    });
  });

  group('SetGitHubTokenRequest', () {
    const request = SetGitHubTokenRequest('ghp_secret');

    test('round-trips through JSON', () {
      expect(request.toJson(), {'token': 'ghp_secret'});
      expect(SetGitHubTokenRequest.fromJson(request.toJson()), request);
    });

    test('never prints the token', () {
      expect('$request', isNot(contains('ghp_secret')));
    });
  });
}
