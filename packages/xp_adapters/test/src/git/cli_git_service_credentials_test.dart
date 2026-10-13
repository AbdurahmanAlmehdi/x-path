import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';

const _token = 'ghp_supersecrettoken1234567890';

void main() {
  late MemorySecretStore secrets;
  late FakeProcessRunner runner;
  late CliGitService service;
  const mirror = GitMirror(githubRepoId: 9, path: '/data/mirrors/9.git');

  CliGitService serviceOn(FakeProcessRunner runner) => CliGitService(
    runner: runner,
    secrets: secrets,
    dataDir: '/data',
    timeout: const Duration(milliseconds: 200),
  );

  setUp(() {
    secrets = MemorySecretStore();
    runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0));
    service = serviceOn(runner);
  });

  group('network commands', () {
    setUp(() => secrets.values[githubTokenSecretKey] = _token);

    test('give git the token through the environment only', () async {
      await service.fetch(mirror);
      await service.push(mirror, refspecs: [GitRefspecs.tag('v1')]);

      for (final call in runner.calls) {
        expect(call.environment?['XPATH_GIT_TOKEN'], _token);
        expect(call.arguments.join(' '), isNot(contains(_token)));
        expect(call.arguments, contains('credential.helper='));
        expect(
          call.arguments,
          contains(startsWith('credential.https://github.com.helper=!')),
        );
        expect(call.workingDirectory, mirror.path);
      }
    });

    test('use a helper that answers only get, from the environment', () async {
      await service.fetch(mirror);
      final helper = runner.calls.single.arguments
          .firstWhere((a) => a.startsWith('credential.https://'))
          .split('helper=')
          .last;
      expect(helper, startsWith('!'));

      Future<String> ask(String operation) async {
        final result = await Process.run(
          'sh',
          ['-c', '${helper.substring(1)} $operation'],
          environment: {'XPATH_GIT_TOKEN': _token},
        );
        return result.stdout as String;
      }

      expect(await ask('get'), 'username=x-access-token\npassword=$_token\n');
      expect(await ask('store'), isEmpty);
      expect(await ask('erase'), isEmpty);
    });

    test('are limited to github.com and reset other helpers', () async {
      await service.fetch(mirror);

      final arguments = runner.calls.single.arguments;
      expect(
        arguments.indexOf('credential.helper='),
        lessThan(
          arguments.indexWhere((a) => a.startsWith('credential.https://')),
        ),
      );
      expect(arguments.where((a) => a.startsWith('credential.')), hasLength(2));
    });

    test('send no credential config without a token', () async {
      secrets.values.clear();

      await service.fetch(mirror);

      final call = runner.calls.single;
      expect(call.environment, isNot(contains('XPATH_GIT_TOKEN')));
      expect(call.arguments.where((a) => a.startsWith('credential.')), isEmpty);
    });
  });

  group('every command', () {
    setUp(() => secrets.values[githubTokenSecretKey] = _token);

    test(
      'ignores user git config, never prompts and never gets the token',
      () async {
        await service.createTag(
          mirror,
          name: 'v1',
          sha: 'a' * 40,
          message: 'm',
        );

        expect(runner.calls, isNotEmpty);
        for (final call in runner.calls) {
          expect(call.executable, 'git');
          expect(call.environment, {
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_TERMINAL_PROMPT': '0',
            'LC_ALL': 'C',
          });
          expect(call.arguments, containsAllInOrder(['-c', 'user.name=XPath']));
          expect(
            call.arguments,
            containsAllInOrder(['-c', 'user.email=xpath@localhost']),
          );
        }
      },
    );

    test('uses the configured identity and executable', () async {
      final custom = CliGitService(
        runner: runner,
        secrets: secrets,
        dataDir: '/data',
        identity: const GitIdentity(name: 'Bot', email: 'bot@example.com'),
        gitExecutable: '/opt/git/bin/git',
      );

      await custom.resolveRef(mirror, 'main');

      expect(runner.calls.first.executable, '/opt/git/bin/git');
      expect(runner.calls.first.arguments, contains('user.name=Bot'));
      expect(
        runner.calls.first.arguments,
        contains('user.email=bot@example.com'),
      );
    });

    test('never forces a push', () async {
      await service.push(
        mirror,
        refspecs: [GitRefspecs.branch('release/1'), GitRefspecs.tag('v1+2')],
      );

      final arguments = runner.calls.single.arguments;
      expect(arguments.where((a) => a.contains('force')), isEmpty);
      expect(arguments.where((a) => a.startsWith('+')), isEmpty);
      expect(arguments, containsAllInOrder(['push', 'origin']));
    });
  });

  group('failures', () {
    test('a push the remote refuses is a GitPushRejectedException', () async {
      runner = FakeProcessRunner(
        (_) => const ProcessOutput(
          exitCode: 1,
          stderr: ' ! [rejected] main -> main (non-fast-forward)\n',
        ),
      );

      await expectLater(
        serviceOn(runner).push(mirror, refspecs: [GitRefspecs.branch('main')]),
        throwsA(
          isA<GitPushRejectedException>().having(
            (e) => e.message,
            'message',
            contains('non-fast-forward'),
          ),
        ),
      );
    });

    test('any other push failure is a plain GitException', () async {
      runner = FakeProcessRunner(
        (_) => const ProcessOutput(exitCode: 128, stderr: 'fatal: no network'),
      );

      await expectLater(
        serviceOn(runner).push(mirror, refspecs: [GitRefspecs.branch('main')]),
        throwsA(
          isA<GitException>()
              .having((e) => e, 'type', isNot(isA<GitPushRejectedException>()))
              .having((e) => e.message, 'message', contains('no network')),
        ),
      );
    });

    test('a fatal rev-parse is an error, not a missing ref', () async {
      runner = FakeProcessRunner(
        (_) => const ProcessOutput(exitCode: 128, stderr: 'fatal: corrupt'),
      );

      await expectLater(
        serviceOn(runner).resolveRef(mirror, 'main'),
        throwsA(
          isA<GitException>()
              .having((e) => e, 'type', isNot(isA<GitRefNotFoundException>()))
              .having((e) => e.message, 'message', contains('corrupt')),
        ),
      );
    });

    test('a fatal merge-base is an error, not "not a descendant"', () async {
      runner = FakeProcessRunner((call) {
        final arguments = call.arguments;
        if (arguments.contains('merge-base')) {
          return const ProcessOutput(exitCode: 128, stderr: 'fatal: bad');
        }
        // `main` already exists locally on another commit than the request.
        final revision = arguments.last;
        return ProcessOutput(
          exitCode: 0,
          stdout: revision.startsWith('refs/heads/b')
              ? '${'a' * 40}\n'
              : '${'b' * 40}\n',
        );
      });

      await expectLater(
        serviceOn(runner).upsertBranch(mirror, name: 'b', sha: 'c' * 40),
        throwsA(
          isA<GitException>()
              .having(
                (e) => e,
                'type',
                isNot(isA<GitBranchConflictException>()),
              )
              .having(
                (e) => e.message,
                'message',
                startsWith('git merge-base'),
              ),
        ),
      );
    });

    test('a command that outlives the timeout is killed', () async {
      runner = FakeProcessRunner((_) => Completer<ProcessOutput>().future);

      await expectLater(
        serviceOn(runner).fetch(mirror),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            startsWith('git fetch timed out'),
          ),
        ),
      );
      expect(runner.calls.single.killed, isTrue);
    });

    test('a missing git is a GitException', () async {
      runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0))
        ..startError = const ProcessStartException('git', 'not found');

      await expectLater(
        serviceOn(runner).fetch(mirror),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            'Cannot run git: not found',
          ),
        ),
      );
    });

    test('a locked secret store stops a network command', () async {
      final locked = _LockedSecretStore();

      await expectLater(
        CliGitService(
          runner: runner,
          secrets: locked,
          dataDir: '/data',
        ).fetch(mirror),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('commit', () {
    test('fails when git cannot compare the staged paths', () async {
      final failing = serviceOn(
        FakeProcessRunner(
          (call) => call.arguments.contains('diff')
              ? const ProcessOutput(exitCode: 129, stderr: 'usage')
              : const ProcessOutput(exitCode: 0),
        ),
      );

      await expectLater(
        failing.commit(
          const GitWorktree(mirror: mirror, path: '/w', sha: 'abc'),
          message: 'm',
          paths: ['pubspec.yaml'],
        ),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            startsWith('git diff failed (exit 129)'),
          ),
        ),
      );
    });
  });
}

class _LockedSecretStore extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('locked');
}
