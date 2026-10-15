import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';

void main() {
  late BytesSecretStore secrets;
  late FakeCredentialVerifier verifier;
  late FakeGitHubCliToken cli;
  late ReplacingMasker masker;
  late GitHubTokenService service;
  final owner = tokenOf(DeviceTokenKind.app);

  setUp(() {
    secrets = BytesSecretStore();
    verifier = FakeCredentialVerifier(CredentialKind.github);
    cli = FakeGitHubCliToken(token: 'gho_from_cli');
    masker = ReplacingMasker();
    service = GitHubTokenService(
      secrets: secrets,
      verifier: verifier,
      cli: cli,
      masker: masker,
    );
  });

  group('status', () {
    test('says there is no token without asking GitHub', () async {
      expect(await service.status(), const GitHubTokenStatus(stored: false));
      await secrets.write(githubTokenSecretKey, '');
      expect(await service.status(), const GitHubTokenStatus(stored: false));
      expect(verifier.checked, isEmpty);
    });

    test('asks GitHub who the stored token belongs to', () async {
      await secrets.write(githubTokenSecretKey, 'ghp_stored');
      verifier.answers.add(const VerificationResult.verified(account: 'octo'));

      expect(
        await service.status(),
        const GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.verified,
          login: 'octo',
        ),
      );
      expect(
        verifier.checked.single,
        isA<TokenMaterial>()
            .having((m) => m.kind, 'kind', CredentialKind.github)
            .having((m) => m.token, 'token', 'ghp_stored'),
      );
      expect(masker.secrets, ['ghp_stored']);
    });

    test('says why GitHub refused the stored token', () async {
      await secrets.write(githubTokenSecretKey, 'ghp_stored');
      verifier.answers.add(
        const VerificationResult.rejected('Refused.', fix: 'Save another.'),
      );

      expect(
        await service.status(),
        const GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.rejected,
          message: 'Refused.',
          fix: 'Save another.',
        ),
      );
    });
  });

  group('save', () {
    test('stores a token GitHub accepts, trimmed', () async {
      verifier.answers.add(const VerificationResult.verified(account: 'octo'));

      final status = await service.save(' ghp_new\n', by: owner);

      expect(
        status,
        const GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.verified,
          login: 'octo',
        ),
      );
      expect(secrets.text(githubTokenSecretKey), 'ghp_new');
      expect(masker.secrets, ['ghp_new']);
    });

    test('stores nothing when GitHub refuses the token', () async {
      await secrets.write(githubTokenSecretKey, 'ghp_old');
      verifier.answers.add(
        const VerificationResult.rejected('Refused.', fix: 'Save another.'),
      );

      await expectLater(
        service.save('ghp_bad', by: owner),
        throwsA(
          isA<CredentialRejectedException>()
              .having((error) => error.message, 'message', 'Refused.')
              .having((error) => error.fix, 'fix', 'Save another.'),
        ),
      );
      expect(secrets.text(githubTokenSecretKey), 'ghp_old');
    });

    test('stores nothing when GitHub cannot be reached', () async {
      verifier.answers.add(
        const VerificationResult.unreachable('Offline.', fix: 'Retry.'),
      );

      await expectLater(
        service.save('ghp_new', by: owner),
        throwsA(
          isA<CredentialUnreachableException>()
              .having((error) => error.message, 'message', 'Offline.')
              .having((error) => error.fix, 'fix', 'Retry.'),
        ),
      );
      expect(secrets.values, isEmpty);
    });

    test('refuses an empty token without asking GitHub', () async {
      await expectLater(
        service.save('  ', by: owner),
        throwsA(isA<CredentialRejectedException>()),
      );
      expect(verifier.checked, isEmpty);
    });

    test('is for the app and xp only', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          service.save('ghp_new', by: tokenOf(kind)),
          throwsA(
            isA<GitHubTokenForbiddenException>().having(
              (error) => error.message,
              'message',
              contains('A ${kind.name} token cannot set the GitHub token'),
            ),
          ),
        );
      }
      await service.save('ghp_new', by: tokenOf(DeviceTokenKind.cli));
      expect(secrets.text(githubTokenSecretKey), 'ghp_new');
    });
  });

  group('importFromCli', () {
    test("checks and stores the GitHub CLI's token", () async {
      final status = await service.importFromCli(by: owner);

      expect(status.status, CredentialStatus.verified);
      expect(secrets.text(githubTokenSecretKey), 'gho_from_cli');
      expect(cli.reads, 1);
    });

    test('turns a missing or logged out gh into a rejection', () async {
      cli.error = const GitHubCliTokenException(
        'gh is not logged in.',
        fix: 'Run gh auth login.',
      );

      await expectLater(
        service.importFromCli(by: owner),
        throwsA(
          isA<CredentialRejectedException>()
              .having((e) => e.message, 'message', 'gh is not logged in.')
              .having((e) => e.fix, 'fix', 'Run gh auth login.'),
        ),
      );
      expect(secrets.values, isEmpty);
      expect('${cli.error}', contains('gh is not logged in.'));
    });

    test('is for the app and xp only', () async {
      await expectLater(
        service.importFromCli(by: tokenOf(DeviceTokenKind.mcp)),
        throwsA(isA<GitHubTokenForbiddenException>()),
      );
      expect(cli.reads, 0);
    });
  });

  group('clear', () {
    test('forgets the token', () async {
      await secrets.write(githubTokenSecretKey, 'ghp_old');

      await service.clear(by: owner);

      expect(secrets.values, isEmpty);
    });

    test('is for the app and xp only', () async {
      await secrets.write(githubTokenSecretKey, 'ghp_old');

      await expectLater(
        service.clear(by: tokenOf(DeviceTokenKind.mcp)),
        throwsA(
          isA<GitHubTokenForbiddenException>().having(
            (error) => '$error',
            'toString',
            contains('cannot remove the GitHub token'),
          ),
        ),
      );
      expect(secrets.text(githubTokenSecretKey), 'ghp_old');
    });
  });
}
