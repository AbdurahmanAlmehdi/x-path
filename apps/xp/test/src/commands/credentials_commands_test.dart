import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/commands/credentials_commands.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUpAll(registerFallbacks);
  setUp(() {
    env = TestEnv();
    when(
      () => env.client.listNamedCredentials(),
    ).thenAnswer((_) async => [sample.ascCredential, sample.slackCredential]);
    when(() => env.client.listProjects())
        .thenAnswer((_) async => [sample.project]);
  });
  tearDown(() => env.dispose());

  /// Writes [contents] to a file in the test's folder and returns its path.
  String file(String name, Object contents) {
    final path = p.join(env.directory.path, name);
    final file = File(path);
    if (contents is String) {
      file.writeAsStringSync(contents);
    } else {
      file.writeAsBytesSync(contents as List<int>);
    }
    return path;
  }

  /// Puts [text] on standard input and ends it.
  void pipe(String text) {
    env.stdin.add(utf8.encode(text));
    unawaited(env.stdin.close());
  }

  /// Everything the command printed, on any stream.
  String printed() => [
    ...env.logger.infos,
    ...env.logger.errors,
    ...env.logger.warnings,
    ...env.logger.successes,
    ...env.logger.details,
  ].join('\n');

  Map<String, dynamic> createdMaterial() =>
      (verify(() => env.client.createCredential(captureAny())).captured.single
              as CreateCredentialRequest)
          .material;

  void answerCreate() =>
      when(() => env.client.createCredential(any()))
          .thenAnswer((_) async => sample.slackCredential);

  group('credentials list', () {
    test('lists the credentials with how many flavors use each', () async {
      await env.runOk(['credentials', 'list']);

      final out = env.logger.out;
      expect(out, contains('NAME'));
      expect(out, contains('USED BY'));
      expect(out, contains('Acme ASC'));
      expect(out, contains('asc_key'));
      expect(out, contains('KEY123'));
      expect(out, contains('2 flavors'));
      expect(out, contains('Team Slack'));
      expect(out, contains('0 flavors'));
    });

    test('says how to add one when there are none', () async {
      when(() => env.client.listNamedCredentials()).thenAnswer((_) async => []);

      await env.runOk(['credentials', 'list']);

      expect(env.logger.out, contains('No credentials'));
      expect(env.logger.out, contains('xp credentials add'));
    });

    test('with --json prints the credentials', () async {
      await env.runOk(['--json', 'credentials', 'list']);

      expect(jsonDecode(env.logger.infos.single), [
        jsonDecode(jsonEncode(sample.ascCredential.toJson())),
        jsonDecode(jsonEncode(sample.slackCredential.toJson())),
      ]);
    });

    test('answers to the singular too', () async {
      await env.runOk(['credential', 'list']);

      expect(env.logger.out, contains('Acme ASC'));
    });

    test('a token that may not is said so', () async {
      when(() => env.client.listNamedCredentials()).thenThrow(
        const ApiException(
          'No.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );

      expect(await env.run(['credentials', 'list']), 77);
      expect(env.logger.errors.single, contains('Not allowed'));
    });
  });

  group('credentials show', () {
    test('shows a credential by name, in any case, with every usage', () async {
      await env.runOk(['credentials', 'show', 'acme asc']);

      final out = env.logger.out;
      expect(out, contains('Acme ASC (crd_1)'));
      expect(out, contains('App Store Connect API key (asc_key)'));
      expect(out, contains('account:  KEY123'));
      expect(out, contains('verified (checked 2026-10-14 09:30)'));
      expect(out, contains('acme/app'));
      expect(out, contains('prj_2'));
      expect(out, contains('rejected'));
      expect(
        out,
        contains(
          'The key cannot see com.acme.other. '
          'fix: Give the key access to the app.',
        ),
      );
    });

    test('shows a credential by id', () async {
      await env.runOk(['credentials', 'show', 'crd_2']);

      final out = env.logger.out;
      expect(out, contains('Team Slack (crd_2)'));
      expect(out, contains('account:  -'));
      expect(out, contains('message:  Slack answered 404.'));
      expect(out, contains('fix:      Make a new webhook.'));
      expect(out, contains('No flavor uses it'));
    });

    test('with --json prints the credential', () async {
      await env.runOk(['--json', 'credentials', 'show', 'crd_1']);

      final shown = jsonDecode(env.logger.infos.single) as Map;
      expect(shown['id'], 'crd_1');
      expect(shown['usedBy'], hasLength(2));
    });

    test('says when there is no such credential', () async {
      final code = await env.run(['credentials', 'show', 'crd_404']);

      expect(code, 66);
      expect(env.logger.errors.single, contains('No credential "crd_404"'));
    });

    test('needs exactly one credential', () async {
      expect(await env.run(['credentials', 'show']), 64);
      expect(await env.run(['credentials', 'show', 'a', 'b']), 64);
    });
  });

  group('credentials add', () {
    test('adds an App Store Connect key from its .p8 file', () async {
      when(() => env.client.createCredential(any()))
          .thenAnswer((_) async => sample.ascCredential);
      final p8 = file('AuthKey.p8', '-----BEGIN PRIVATE KEY-----\nabc\n');

      await env.runOk([
        'credentials',
        'add',
        '--kind',
        'asc_key',
        '--name',
        '  Acme ASC  ',
        '--key-id',
        'KEY123',
        '--issuer-id',
        'iss-1',
        '--p8',
        p8,
        '--key-kind',
        'individual',
      ]);

      final request =
          verify(() => env.client.createCredential(captureAny()))
                  .captured
                  .single
              as CreateCredentialRequest;
      expect(request.name, 'Acme ASC');
      expect(request.kind, CredentialKind.ascKey);
      expect(request.material, {
        'keyId': 'KEY123',
        'issuerId': 'iss-1',
        'privateKey': '-----BEGIN PRIVATE KEY-----\nabc\n',
        'keyKind': 'individual',
      });
      expect(env.logger.out, contains('Added "Acme ASC"'));
      expect(env.logger.out, contains('crd_1'));
      expect(printed(), isNot(contains('BEGIN PRIVATE KEY')));
    });

    test('leaves the key kind to the engine when not given', () async {
      answerCreate();
      final p8 = file('AuthKey.p8', 'key');

      await env.runOk([
        'credentials',
        'add',
        '--kind=asc_key',
        '--name=K',
        '--key-id=K',
        '--issuer-id=I',
        '--p8=$p8',
      ]);

      expect(createdMaterial().containsKey('keyKind'), isFalse);
    });

    test('asks for the password of an Apple ID at a terminal', () async {
      answerCreate();
      env.prompt
        ..interactive = true
        ..answers.add('abcd-efgh-ijkl-mnop');

      await env.runOk([
        'credentials',
        'add',
        '--kind',
        'apple_id',
        '--name',
        'Apple',
        '--apple-id',
        'me@example.com',
      ]);

      expect(env.prompt.questions, ['App-specific password']);
      expect(createdMaterial(), {
        'appleId': 'me@example.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });
      expect(printed(), isNot(contains('abcd-efgh-ijkl-mnop')));
    });

    test('reads the password of an Apple ID from standard input', () async {
      answerCreate();
      pipe('abcd-efgh-ijkl-mnop\n');

      await env.runOk([
        '--verbose',
        'credentials',
        'add',
        '--kind',
        'apple_id',
        '--name',
        'Apple',
        '--apple-id',
        'me@example.com',
        '--password-stdin',
      ]);

      expect(env.prompt.questions, isEmpty);
      expect(createdMaterial()['password'], 'abcd-efgh-ijkl-mnop');
      expect(printed(), isNot(contains('abcd-efgh-ijkl-mnop')));
    });

    test(
      'without a terminal names the option that reads standard input',
      () async {
        final code = await env.run([
          'credentials',
          'add',
          '--kind',
          'apple_id',
          '--name',
          'Apple',
          '--apple-id',
          'me@example.com',
        ]);

        expect(code, 64);
        expect(env.logger.errors.single, contains('--password-stdin'));
        verifyNever(() => env.client.createCredential(any()));
      },
    );

    test('refuses an empty answer', () async {
      env.prompt
        ..interactive = true
        ..answers.add('');

      final code = await env.run([
        'credentials',
        'add',
        '--kind',
        'shorebird',
        '--name',
        'SB',
      ]);

      expect(code, 64);
      expect(env.logger.errors.single, contains('is empty'));
      verifyNever(() => env.client.createCredential(any()));
    });

    test('refuses empty standard input', () async {
      pipe('\n');

      final code = await env.run([
        'credentials',
        'add',
        '--kind',
        'shorebird',
        '--name',
        'SB',
        '--token-stdin',
      ]);

      expect(code, 64);
      expect(env.logger.errors.single, contains('Standard input had no'));
      verifyNever(() => env.client.createCredential(any()));
    });

    for (final kind in ['play_sa', 'firebase_sa']) {
      test('adds a $kind from its JSON key file', () async {
        answerCreate();
        final json = file('sa.json', '{"client_email": "x@y"}');

        await env.runOk([
          'credentials',
          'add',
          '--kind',
          kind,
          '--name',
          'SA',
          '--service-account',
          json,
        ]);

        expect(createdMaterial(), {
          'serviceAccount': '{"client_email": "x@y"}',
        });
      });
    }

    test('adds a keystore, its passwords from standard input and the '
        'terminal', () async {
      answerCreate();
      final keystore = file('release.jks', [0, 1, 2, 255]);
      env.prompt.interactive = true;
      env.prompt.answers.add('key-secret');
      pipe('store-secret\r\n');

      await env.runOk([
        'credentials',
        'add',
        '--kind',
        'keystore',
        '--name',
        'Upload key',
        '--keystore',
        keystore,
        '--key-alias',
        'upload',
        '--store-password-stdin',
      ]);

      expect(env.prompt.questions, [
        'Key password (empty: the keystore password)',
      ]);
      expect(createdMaterial(), {
        'keystore': base64Encode([0, 1, 2, 255]),
        'keyAlias': 'upload',
        'storePassword': 'store-secret',
        'keyPassword': 'key-secret',
      });
      expect(printed(), isNot(contains('secret')));
    });

    test('leaves the key password out when it is the keystore one', () async {
      answerCreate();
      final keystore = file('release.jks', [1]);
      env.prompt
        ..interactive = true
        ..answers.addAll(['store-secret', '']);

      await env.runOk([
        'credentials',
        'add',
        '--kind',
        'keystore',
        '--name',
        'Upload key',
        '--keystore',
        keystore,
        '--key-alias',
        'upload',
      ]);

      final material = createdMaterial();
      expect(material.containsKey('keyPassword'), isFalse);
      expect(material['storePassword'], 'store-secret');
    });

    test('without a terminal a keystore takes the store password from '
        'standard input only', () async {
      answerCreate();
      final keystore = file('release.jks', [1]);
      pipe('store-secret');

      await env.runOk([
        'credentials',
        'add',
        '--kind',
        'keystore',
        '--name',
        'Upload key',
        '--keystore',
        keystore,
        '--key-alias',
        'upload',
        '--store-password-stdin',
      ]);

      expect(env.prompt.questions, isEmpty);
      expect(createdMaterial().containsKey('keyPassword'), isFalse);
    });

    test(
      'reads standard input once: two --*-stdin options are refused',
      () async {
        final keystore = file('release.jks', [1]);

        final code = await env.run([
          'credentials',
          'add',
          '--kind',
          'keystore',
          '--name',
          'Upload key',
          '--keystore',
          keystore,
          '--key-alias',
          'upload',
          '--store-password-stdin',
          '--key-password-stdin',
        ]);

        expect(code, 64);
        expect(env.logger.errors.single, contains('only one of'));
        expect(env.logger.errors.single, contains('read once'));
        verifyNever(() => env.client.createCredential(any()));
      },
    );

    test(
      'adds a Shorebird key and a Slack webhook from standard input',
      () async {
        answerCreate();
        pipe('sb_api_secret\n');

        await env.runOk([
          'credentials',
          'add',
          '--kind',
          'shorebird',
          '--name',
          'SB',
          '--token-stdin',
        ]);

        expect(createdMaterial(), {'token': 'sb_api_secret'});
        expect(printed(), isNot(contains('sb_api_secret')));
      },
    );

    test('adds a Slack webhook asked for at the terminal', () async {
      answerCreate();
      env.prompt
        ..interactive = true
        ..answers.add('https://hooks.slack.com/services/T/B/x');

      await env.runOk([
        '--json',
        'credentials',
        'add',
        '--kind',
        'slack',
        '--name',
        'Team Slack',
      ]);

      expect(createdMaterial(), {
        'webhookUrl': 'https://hooks.slack.com/services/T/B/x',
      });
      expect(
        jsonDecode(env.logger.infos.single),
        jsonDecode(jsonEncode(sample.slackCredential.toJson())),
      );
      expect(printed(), isNot(contains('hooks.slack.com')));
    });

    test('has no option that takes a secret as an argument', () {
      for (final command in ['add', 'replace']) {
        final options = env
            .runner
            .commands['credentials']!
            .subcommands[command]!
            .argParser
            .options;
        for (final secret in [
          'password',
          'token',
          'webhook-url',
          'store-password',
          'key-password',
          'secret',
        ]) {
          expect(options, isNot(contains(secret)), reason: command);
        }
        for (final option in options.values) {
          if (option.name.endsWith('-stdin')) {
            expect(option.isFlag, isTrue, reason: option.name);
          }
        }
      }
    });

    test('refuses a secret given as an argument', () async {
      final code = await env.run([
        'credentials',
        'add',
        '--kind',
        'shorebird',
        '--name',
        'SB',
        '--token',
        'sb_api_secret',
      ]);

      expect(code, 64);
      expect(printed(), isNot(contains('sb_api_secret')));
      verifyNever(() => env.client.createCredential(any()));
    });

    test('points a GitHub token to the engine token', () async {
      final code = await env.run([
        'credentials',
        'add',
        '--kind',
        'github',
        '--name',
        'GH',
      ]);

      expect(code, 64);
      expect(env.logger.errors.single, contains('not a named credential'));
      expect(env.logger.errors.single, contains('xpd secrets import-gh'));
    });

    test('says what is wrong with the options', () async {
      Future<String> refused(List<String> arguments) async {
        env.logger.errors.clear();
        expect(await env.run(['credentials', 'add', ...arguments]), 64);
        return env.logger.errors.single;
      }

      expect(await refused(['--name', 'x']), contains('Missing --kind'));
      expect(
        await refused(['--kind', 'nope', '--name', 'x']),
        contains('Unknown --kind "nope"'),
      );
      expect(await refused(['--kind', 'slack']), contains('Missing --name'));
      expect(
        await refused(['--kind', 'slack', '--name', '   ']),
        contains('The name must be a non-empty string'),
      );
      expect(
        await refused(['--kind', 'slack', '--name', 'x' * 81]),
        contains('at most 80'),
      );
      expect(
        await refused(['--kind', 'slack', '--name', 'a\tb']),
        contains('control characters'),
      );
      expect(
        await refused(['--kind', 'slack', '--name', 'x', '--key-id', 'K']),
        contains('--key-id is not for --kind slack'),
      );
      expect(
        await refused(['--kind', 'asc_key', '--name', 'x', '--key-id', 'K']),
        contains('Missing --issuer-id (for --kind asc_key)'),
      );
      expect(
        await refused(['--kind', 'slack', '--name', 'x', 'extra']),
        contains('Unexpected "extra"'),
      );
      verifyNever(() => env.client.createCredential(any()));
    });

    test('says when a file cannot be read', () async {
      final code = await env.run([
        'credentials',
        'add',
        '--kind',
        'play_sa',
        '--name',
        'SA',
        '--service-account',
        p.join(env.directory.path, 'missing.json'),
      ]);

      expect(code, 66);
      expect(env.logger.errors.single, contains('Cannot read'));
      expect(env.logger.errors.single, contains('missing.json'));
    });

    group('the engine', () {
      Future<int> addSlack() {
        pipe('https://hooks.slack.com/services/T/B/x');
        return env.run([
          'credentials',
          'add',
          '--kind',
          'slack',
          '--name',
          'Team Slack',
          '--webhook-url-stdin',
        ]);
      }

      void fail(ApiException error) =>
          when(() => env.client.createCredential(any())).thenThrow(error);

      test('refusing the credential is invalid content', () async {
        fail(
          const ApiException(
            'Slack answered 404: the webhook does not exist.',
            statusCode: 422,
            code: ApiErrorCode.credentialRejected,
          ),
        );

        expect(await addSlack(), 65);
        expect(env.logger.errors.single, contains('Slack answered 404'));
        expect(printed(), isNot(contains('hooks.slack.com')));
      });

      test('not reaching the store is unavailable', () async {
        fail(
          const ApiException(
            'Slack cannot be reached.',
            statusCode: 502,
            code: ApiErrorCode.upstreamError,
          ),
        );

        expect(await addSlack(), 69);
      });

      test('a name that is taken is a conflict', () async {
        fail(
          const ApiException(
            'A credential called "Team Slack" exists already.',
            statusCode: 409,
            code: ApiErrorCode.conflict,
          ),
        );

        expect(await addSlack(), 73);
        expect(env.logger.errors.single, contains('exists already'));
      });

      test('a token that may not is a permission error', () async {
        fail(
          const ApiException(
            'An mcp token cannot add a credential.',
            statusCode: 403,
            code: ApiErrorCode.forbidden,
          ),
        );

        expect(await addSlack(), 77);
      });

      test('an engine that cannot be reached', () async {
        when(() => env.client.createCredential(any()))
            .thenThrow(const ConnectionException('Cannot reach the engine.'));

        expect(await addSlack(), 69);
      });
    });
  });

  group('credentials rename', () {
    test('renames by name', () async {
      when(() => env.client.renameCredential('crd_1', 'Acme key')).thenAnswer(
        (_) async => const NamedCredential(
          id: 'crd_1',
          name: 'Acme key',
          kind: CredentialKind.ascKey,
          status: CredentialStatus.verified,
        ),
      );

      await env.runOk(['credentials', 'rename', 'Acme ASC', ' Acme key ']);

      expect(env.logger.out, 'Renamed "Acme ASC" to "Acme key" (crd_1).');
    });

    test('with --json prints the credential', () async {
      when(() => env.client.renameCredential(any(), any()))
          .thenAnswer((_) async => sample.slackCredential);

      await env.runOk(['--json', 'credentials', 'rename', 'crd_2', 'x']);

      expect((jsonDecode(env.logger.infos.single) as Map)['id'], 'crd_2');
    });

    test('refuses a bad name before asking the engine', () async {
      expect(await env.run(['credentials', 'rename', 'crd_1', '']), 64);
      verifyNever(() => env.client.listNamedCredentials());
    });

    test('a name that is taken is a conflict', () async {
      when(() => env.client.renameCredential(any(), any())).thenThrow(
        const ApiException(
          'Taken.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );

      expect(await env.run(['credentials', 'rename', 'crd_1', 'x']), 73);
    });

    test('needs the credential and the new name', () async {
      expect(await env.run(['credentials', 'rename', 'crd_1']), 64);
    });
  });

  group('credentials replace', () {
    test('gives the credential a new secret of its kind', () async {
      when(() => env.client.replaceCredentialSecret(any(), any()))
          .thenAnswer((_) async => sample.slackCredential);
      pipe('https://hooks.slack.com/services/T/B/new\n');

      await env.runOk([
        'credentials',
        'replace',
        'team slack',
        '--webhook-url-stdin',
      ]);

      final [id, request] = verify(
        () => env.client.replaceCredentialSecret(captureAny(), captureAny()),
      ).captured;
      expect(id, 'crd_2');
      expect((request as ReplaceCredentialRequest).material, {
        'webhookUrl': 'https://hooks.slack.com/services/T/B/new',
      });
      expect(env.logger.out, contains('Replaced the secret of "Team Slack"'));
      expect(printed(), isNot(contains('hooks.slack.com')));
    });

    test('takes the options of the kind of the credential', () async {
      final code = await env.run([
        'credentials',
        'replace',
        'Acme ASC',
        '--webhook-url-stdin',
      ]);

      expect(code, 64);
      expect(
        env.logger.errors.single,
        contains('--webhook-url-stdin is not for --kind asc_key'),
      );
    });

    test('with --json prints the credential', () async {
      when(() => env.client.replaceCredentialSecret(any(), any()))
          .thenAnswer((_) async => sample.ascCredential);
      final p8 = file('k.p8', 'key');

      await env.runOk([
        '--json',
        'credentials',
        'replace',
        'crd_1',
        '--key-id',
        'K',
        '--issuer-id',
        'I',
        '--p8',
        p8,
      ]);

      expect((jsonDecode(env.logger.infos.single) as Map)['id'], 'crd_1');
    });

    test('the engine refusing the new secret is invalid content', () async {
      when(() => env.client.replaceCredentialSecret(any(), any())).thenThrow(
        const ApiException(
          'Refused.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      );
      pipe('https://hooks.slack.com/services/T/B/new');

      expect(
        await env.run([
          'credentials',
          'replace',
          'crd_2',
          '--webhook-url-stdin',
        ]),
        65,
      );
    });
  });

  group('credentials verify', () {
    test('exits 0 when every check accepts it', () async {
      const fine = NamedCredential(
        id: 'crd_1',
        name: 'Acme ASC',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.verified,
      );
      when(() => env.client.verifyNamedCredential('crd_1'))
          .thenAnswer((_) async => fine);

      await env.runOk(['credentials', 'verify', 'Acme ASC']);

      expect(env.logger.out, contains('status:   verified'));
    });

    test('exits 1 when a flavor cannot use it', () async {
      when(() => env.client.verifyNamedCredential('crd_1'))
          .thenAnswer((_) async => sample.ascCredential);

      expect(await env.run(['credentials', 'verify', 'crd_1']), 1);
      expect(env.logger.out, contains('Give the key access to the app.'));
    });

    test('exits 1 when the credential itself is refused', () async {
      when(() => env.client.verifyNamedCredential('crd_2'))
          .thenAnswer((_) async => sample.slackCredential);

      expect(await env.run(['--json', 'credentials', 'verify', 'crd_2']), 1);
      expect(
        (jsonDecode(env.logger.infos.single) as Map)['status'],
        'rejected',
      );
    });
  });

  group('credentials remove', () {
    test('deletes a credential no flavor uses', () async {
      when(() => env.client.deleteNamedCredential('crd_2'))
          .thenAnswer((_) async {});

      await env.runOk(['credentials', 'remove', 'Team Slack']);

      expect(env.logger.out, 'Deleted "Team Slack" (crd_2).');
    });

    test('lists the flavors of a credential in use and says how to '
        'force it', () async {
      when(() => env.client.deleteNamedCredential('crd_1')).thenThrow(
        ApiException(
          'The credential is in use.',
          statusCode: 409,
          code: ApiErrorCode.credentialInUse,
          usedBy: sample.ascCredential.usedBy,
        ),
      );

      final code = await env.run(['credentials', 'remove', 'Acme ASC']);

      expect(code, 73);
      final error = env.logger.errors.single;
      expect(error, contains('"Acme ASC" is used by 2 flavors'));
      expect(error, contains('acme/app'));
      expect(error, contains('prj_2'));
      expect(error, contains('default'));
      expect(error, contains('xp credentials remove "Acme ASC" --force'));
    });

    test('with --force removes it from every flavor and deletes it', () async {
      when(() => env.client.deleteNamedCredential('crd_1', force: true))
          .thenAnswer((_) async {});

      await env.runOk(['credentials', 'remove', 'crd_1', '--force']);

      expect(
        env.logger.out,
        'Removed "Acme ASC" from 2 flavors and deleted it (crd_1).',
      );
    });

    test('with --json prints what it removed', () async {
      when(() => env.client.deleteNamedCredential('crd_2'))
          .thenAnswer((_) async {});

      await env.runOk(['--json', 'credentials', 'remove', 'crd_2']);

      expect(jsonDecode(env.logger.infos.single), {
        'removed': 'crd_2',
        'name': 'Team Slack',
      });
    });

    test('passes other errors on', () async {
      when(() => env.client.deleteNamedCredential('crd_2')).thenThrow(
        const ApiException(
          'No.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );

      expect(await env.run(['credentials', 'remove', 'crd_2']), 77);
    });
  });

  group('credentials assign', () {
    void answerAssign(AssignCredentialResponse response) => when(
      () => env.client.assignCredential(
        any(),
        flavor: any(named: 'flavor'),
        kind: any(named: 'kind'),
        request: any(named: 'request'),
        app: any(named: 'app'),
      ),
    ).thenAnswer((_) async => response);

    List<Object?> assignedWith() => verify(
      () => env.client.assignCredential(
        captureAny(),
        flavor: captureAny(named: 'flavor'),
        kind: captureAny(named: 'kind'),
        request: captureAny(named: 'request'),
        app: captureAny(named: 'app'),
      ),
    ).captured;

    test('makes one flavor use the credential', () async {
      answerAssign(
        AssignCredentialResponse(
          assigned: [
            sample.assigned(
              'prod',
              status: CredentialStatus.rejected,
              message: 'Cannot see the app.',
              fix: 'Grant access.',
            ),
          ],
        ),
      );

      await env.runOk([
        'credentials',
        'assign',
        'Acme ASC',
        '--project',
        'acme/app',
        '--flavor',
        'prod',
      ]);

      expect(assignedWith(), [
        'prj_1',
        'prod',
        CredentialKind.ascKey,
        const AssignCredentialRequest(credentialId: 'crd_1'),
        '.',
      ]);
      final out = env.logger.out;
      expect(out, contains('Assigned "Acme ASC" (asc_key) to 1 flavor:'));
      expect(out, contains('Cannot see the app. fix: Grant access.'));
    });

    test('every flavor: assigns from a flavor without one and reports the '
        'flavors that kept theirs', () async {
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);
      when(() => env.client.listCredentials('prj_1', app: '.')).thenAnswer(
        (_) async => [
          sample.assigned('prod', id: 'crd_9', name: 'Old key'),
          sample.assigned('prod', id: 'crd_8', kind: CredentialKind.slack),
        ],
      );
      answerAssign(
        AssignCredentialResponse(
          assigned: [sample.assigned('dev')],
          kept: [sample.assigned('prod', id: 'crd_9', name: 'Old key')],
        ),
      );

      await env.runOk([
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--all-flavors',
      ]);

      expect(assignedWith(), [
        'prj_1',
        'dev',
        CredentialKind.ascKey,
        const AssignCredentialRequest(credentialId: 'crd_1', allFlavors: true),
        '.',
      ]);
      final out = env.logger.out;
      expect(out, contains('to 1 flavor'));
      expect(out, contains('Kept their own asc_key credential'));
      expect(out, contains('--replace'));
      expect(out, contains('Old key'));
    });

    test('every flavor with --replace assigns from the first', () async {
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);
      when(() => env.client.listCredentials('prj_1', app: '.')).thenAnswer(
        (_) async => [
          sample.assigned('prod', id: 'crd_9'),
          sample.assigned('dev', id: 'crd_9'),
        ],
      );
      answerAssign(
        AssignCredentialResponse(
          assigned: [sample.assigned('prod'), sample.assigned('dev')],
        ),
      );

      await env.runOk([
        '--json',
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--all-flavors',
        '--replace',
      ]);

      final captured = assignedWith();
      expect(captured[1], 'prod');
      expect(
        captured[3],
        const AssignCredentialRequest(
          credentialId: 'crd_1',
          allFlavors: true,
          replace: true,
        ),
      );
      expect(
        (jsonDecode(env.logger.infos.single) as Map)['assigned'],
        hasLength(2),
      );
    });

    test('every flavor: nothing changes when each has its own', () async {
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);
      when(() => env.client.listCredentials('prj_1', app: '.')).thenAnswer(
        (_) async => [
          sample.assigned('prod', id: 'crd_9', name: null),
          sample.assigned('dev', id: 'crd_9', name: null),
        ],
      );

      await env.runOk([
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--all-flavors',
      ]);

      expect(env.logger.out, contains('Nothing changed'));
      expect(env.logger.out, contains('crd_9'));
      verifyNever(
        () => env.client.assignCredential(
          any(),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
          request: any(named: 'request'),
          app: any(named: 'app'),
        ),
      );
    });

    test('every flavor of an app the project does not have', () async {
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      final code = await env.run([
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--app',
        'packages/x',
        '--all-flavors',
      ]);

      expect(code, 66);
      expect(env.logger.errors.single, contains('No app with flavors'));
      expect(env.logger.errors.single, contains('Apps: .'));
    });

    test('passes the app on', () async {
      answerAssign(const AssignCredentialResponse(assigned: []));

      await env.runOk([
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--app',
        'apps/mobile',
        '--flavor',
        'prod',
      ]);

      expect(assignedWith().last, 'apps/mobile');
    });

    test('says what is wrong with the options', () async {
      Future<String> refused(List<String> arguments) async {
        env.logger.errors.clear();
        expect(
          await env.run(['credentials', 'assign', 'crd_1', ...arguments]),
          64,
        );
        return env.logger.errors.single;
      }

      expect(
        await refused(['--flavor', 'prod']),
        contains('Missing --project'),
      );
      expect(
        await refused(['--project', 'p']),
        contains('Missing --flavor (or --all-flavors)'),
      );
      expect(
        await refused(['--project', 'p', '--flavor', 'a', '--all-flavors']),
        contains('not both'),
      );
      expect(
        await refused(['--project', 'p', '--flavor', 'a', '--replace']),
        contains('--replace goes with --all-flavors'),
      );
    });

    test('a flavor the project does not have is not found', () async {
      when(
        () => env.client.assignCredential(
          any(),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
          request: any(named: 'request'),
          app: any(named: 'app'),
        ),
      ).thenThrow(
        const ApiException(
          'No flavor "qa".',
          statusCode: 404,
          code: ApiErrorCode.notFound,
        ),
      );

      final code = await env.run([
        'credentials',
        'assign',
        'crd_1',
        '--project',
        'prj_1',
        '--flavor',
        'qa',
      ]);

      expect(code, 66);
    });
  });

  group('credentials unassign', () {
    test('makes a flavor stop using the credential', () async {
      when(() => env.client.listCredentials('prj_1', app: '.', flavor: 'prod'))
          .thenAnswer(
            (_) async => [
              sample.assigned('prod', id: 'crd_8', kind: CredentialKind.slack),
              sample.assigned('prod'),
            ],
          );
      when(
        () => env.client.unassignCredential(
          'prj_1',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
        ),
      ).thenAnswer((_) async {});

      await env.runOk([
        'credentials',
        'unassign',
        'Acme ASC',
        '--project',
        'acme/app',
        '--flavor',
        'prod',
      ]);

      expect(
        env.logger.out,
        contains('The flavor "prod" of the app "." no longer uses "Acme ASC"'),
      );
      expect(env.logger.out, contains('App Store Connect API key'));
    });

    test('with --json prints what it unassigned', () async {
      when(
        () =>
            env.client.listCredentials('prj_1', app: 'apps/a', flavor: 'prod'),
      ).thenAnswer(
        (_) async => [
          const Credential(
            id: 'crd_1',
            projectId: 'prj_1',
            app: 'apps/a',
            flavor: 'prod',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
        ],
      );
      when(
        () => env.client.unassignCredential(
          'prj_1',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          app: 'apps/a',
        ),
      ).thenAnswer((_) async {});

      await env.runOk([
        '--json',
        'credentials',
        'unassign',
        'crd_1',
        '--project',
        'prj_1',
        '--app',
        'apps/a',
        '--flavor',
        'prod',
      ]);

      expect(jsonDecode(env.logger.infos.single), {
        'unassigned': 'crd_1',
        'projectId': 'prj_1',
        'app': 'apps/a',
        'flavor': 'prod',
        'kind': 'asc_key',
      });
    });

    test('says when the flavor does not use the credential', () async {
      when(() => env.client.listCredentials('prj_1', app: '.', flavor: 'dev'))
          .thenAnswer((_) async => [sample.assigned('dev', id: 'crd_9')]);

      final code = await env.run([
        'credentials',
        'unassign',
        'crd_1',
        '--project',
        'prj_1',
        '--flavor',
        'dev',
      ]);

      expect(code, 66);
      expect(env.logger.errors.single, contains('does not use "Acme ASC"'));
      verifyNever(
        () => env.client.unassignCredential(
          any(),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
          app: any(named: 'app'),
        ),
      );
    });

    test('needs --project and --flavor', () async {
      expect(
        await env.run(['credentials', 'unassign', 'crd_1', '--flavor', 'x']),
        64,
      );
      expect(
        await env.run(['credentials', 'unassign', 'crd_1', '--project', 'p']),
        64,
      );
      expect(env.logger.errors.last, contains('Missing --flavor'));
    });
  });

  test('describeCredential is what show prints', () {
    expect(
      describeCredential(sample.slackCredential),
      startsWith('Team Slack (crd_2)\nkind:     Slack webhook (slack)'),
    );
  });

  test('the help of add explains how secrets are given', () {
    final add = env.runner.commands['credentials']!.subcommands['add']!;

    expect(add.usage, contains('never an argument'));
    expect(add.usage, contains('--token-stdin'));
    expect(add.usage, contains('asc_key (App Store Connect API key)'));
    expect(add, isA<Command<int>>());
  });
}
