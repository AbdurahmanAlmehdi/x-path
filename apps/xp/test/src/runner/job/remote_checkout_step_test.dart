import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/job/remote_checkout_step.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/step_contexts.dart';

final String _sha = 'a' * 40;

const _repository = LeaseRepository(
  githubRepoId: 42,
  sshUrl: 'git@github.com:owner/app.git',
);

GitCheckoutInput _input(String root) => GitCheckoutInput(
  worktree: ReleaseWorktree(
    path: p.join(root, 'source', 'worktrees', '42', 'job_1'),
    mirror: GitMirror(
      githubRepoId: 42,
      path: p.join(root, 'source', 'mirrors', '42.git'),
    ),
    sha: 'f' * 40,
  ),
);

void main() {
  late Directory root;
  late SerialQueues queues;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_checkout_');
    addTearDown(() => root.deleteSync(recursive: true));
    queues = SerialQueues();
  });

  RemoteCheckoutStep step({
    LeaseRepository? repository = _repository,
    String? sha,
    String? testUrl,
  }) => RemoteCheckoutStep(
    source: LeaseSource(repository: repository, sha: sha ?? _sha),
    queues: queues,
    testUrl: testUrl,
  );

  String message(StepOutcome<GitCheckoutResult> outcome) =>
      (outcome as StepFailed).message;

  test('is the git.checkout step, without side effects', () {
    final checkout = step();

    expect(checkout.kind, 'git.checkout');
    expect(checkout.sideEffectOf(_input(root.path)), isFalse);
    expect(
      checkout.decodeInput(checkout.encodeInput(_input(root.path))),
      _input(root.path),
    );
    expect(checkout.encodeResult(GitCheckoutResult(path: '/w', sha: _sha)), {
      'path': '/w',
      'sha': _sha,
    });
  });

  group('what the offer must say', () {
    test('needs a repository', () async {
      final outcome = await step(repository: null)
          .run(_input(root.path), ScriptedContext((_) => const FakeRun()));

      expect(message(outcome), contains('named no repository'));
    });

    test('needs a commit', () async {
      final context = ScriptedContext((_) => const FakeRun());
      final checkout = RemoteCheckoutStep(
        source: const LeaseSource(repository: _repository),
        queues: queues,
      );

      final outcome = await checkout.run(_input(root.path), context);

      expect(message(outcome), contains('named no commit'));
      expect(message(outcome), contains('made no version commit'));
      expect(context.commands, isEmpty);
    });

    test('needs a full commit id', () async {
      final outcome = await step(sha: 'main')
          .run(_input(root.path), ScriptedContext((_) => const FakeRun()));

      expect(message(outcome), contains('"main", which is not a full commit'));
    });
  });

  group('the commands', () {
    late ScriptedContext context;
    late String mirror;

    setUp(() {
      mirror = p.join(root.path, 'source', 'mirrors', '42.git');
      context = ScriptedContext((command) {
        final git = command.arguments.join(' ');
        if (git.startsWith('cat-file')) return const FakeRun(exitCode: 1);
        if (git.startsWith('rev-parse')) return FakeRun(lines: [_sha]);
        return const FakeRun();
      });
    });

    String describe(ProcessCommand command) =>
        '${p.basename(command.workingDirectory!)}: '
        '${command.arguments.join(' ')}';

    test('fetches the commit and checks it out in a worktree', () async {
      final outcome = await step().run(_input(root.path), context);
      final worktree = p.join(root.path, 'source', 'worktrees', '42', 'job_1');

      expect(
        outcome,
        isA<StepSucceeded<GitCheckoutResult>>()
            .having((o) => o.result.sha, 'sha', _sha)
            .having(
              (o) => o.result.path,
              'path',
              p.join(root.path, 'source', 'worktrees', '42', 'job_1'),
            ),
      );
      expect(context.commands.map(describe), [
        'source: -c init.defaultBranch=main init --bare --quiet $mirror',
        '42.git: config remote.origin.url git@github.com:owner/app.git',
        '42.git: cat-file -e $_sha^{commit}',
        '42.git: fetch --no-tags origin $_sha',
        '42.git: update-ref refs/xpath/$_sha $_sha',
        '42.git: worktree prune',
        '42.git: worktree prune',
        '42.git: worktree add --detach $worktree $_sha',
        'job_1: rev-parse HEAD',
      ]);
    });

    test(
      'lets only the fetch use the network, and never ask for a password',
      () async {
        await step().run(_input(root.path), context);

        for (final command in context.commands) {
          expect(command.executable, 'git');
          expect(command.environment['GIT_TERMINAL_PROMPT'], '0');
          expect(command.environment['GIT_CONFIG_GLOBAL'], '/dev/null');
          expect(command.environment['GIT_CONFIG_NOSYSTEM'], '1');
          expect(command.passThroughEnvironment, ['SSH_AUTH_SOCK']);
          final fetches = command.arguments.contains('fetch');
          expect(
            command.environment['GIT_SSH_COMMAND'],
            fetches ? contains('BatchMode=yes') : isNull,
            reason: command.arguments.join(' '),
          );
        }
      },
    );

    test('makes the cache once, and not fetches what it has', () async {
      Directory(mirror).createSync(recursive: true);
      File(p.join(mirror, 'HEAD')).writeAsStringSync('ref: refs/heads/main');
      context.handler = (command) {
        final git = command.arguments.join(' ');
        if (git.startsWith('rev-parse')) return FakeRun(lines: [_sha]);
        return const FakeRun();
      };

      final outcome = await step().run(_input(root.path), context);

      expect(outcome, isA<StepSucceeded<GitCheckoutResult>>());
      final verbs = context.commands.map((c) => c.arguments.first).toList();
      expect(verbs, isNot(contains('init')));
      expect(verbs, isNot(contains('fetch')));
    });

    test('replaces a worktree of the job that is there', () async {
      final worktree = Directory(
        p.join(root.path, 'source', 'worktrees', '42', 'job_1'),
      )..createSync(recursive: true);
      File(p.join(worktree.path, 'old.txt')).writeAsStringSync('old');

      await step().run(_input(root.path), context);

      expect(
        worktree.existsSync() &&
            File(p.join(worktree.path, 'old.txt')).existsSync(),
        isFalse,
      );
    });

    test('takes the url of a test instead of the one of the offer', () async {
      await step(testUrl: '/tmp/origin.git').run(_input(root.path), context);

      final config = context.commands.firstWhere(
        (c) => c.arguments.first == 'config',
      );
      expect(config.arguments.last, '/tmp/origin.git');
    });

    test('names the repository by its id, whatever its name is now', () async {
      await step().run(_input(root.path), context);

      expect(
        context.commands.map((c) => c.workingDirectory),
        contains(endsWith('42.git')),
      );
    });
  });

  group('when something fails', () {
    late List<String> printed;
    late int failingExit;
    late String failing;
    late ScriptedContext context;

    setUp(() {
      printed = [];
      failingExit = 128;
      failing = 'fetch';
      context = ScriptedContext((command) {
        final verb = command.arguments.contains('-c')
            ? 'init'
            : command.arguments.first;
        if (verb == 'cat-file') return const FakeRun(exitCode: 1);
        if (verb == 'rev-parse') return FakeRun(lines: [_sha]);
        if (verb == failing) {
          return FakeRun(exitCode: failingExit, lines: printed);
        }
        return const FakeRun();
      });
    });

    Future<String> failure() async =>
        message(await step().run(_input(root.path), context));

    test('says what to do when the key cannot read the repository', () async {
      printed = [
        'err:git@github.com: Permission denied (publickey).',
        'err:fatal: Could not read from remote repository.',
      ];

      final text = await failure();

      expect(text, contains('cannot read owner/app over SSH'));
      expect(
        text,
        contains("add this runner's SSH key as a deploy key on owner/app"),
      );
    });

    test('recognises a repository the key does not know', () async {
      printed = ['err:ERROR: Repository not found.'];

      expect(await failure(), contains('deploy key on owner/app'));
    });

    test('says what to do about a host key SSH does not trust', () async {
      printed = ['err:Host key verification failed.'];

      final text = await failure();

      expect(text, contains('does not trust the host key'));
      expect(text, contains('ssh -T git@github.com'));
    });

    test('says when the commit was never pushed', () async {
      printed = ['err:fatal: remote error: upload-pack: not our ref $_sha'];

      final text = await failure();

      expect(text, contains('no commit aaaaaaaaaaaa'));
      expect(text, contains('Push it'));
    });

    test('says something plain about any other failure', () async {
      printed = ['err:fatal: unable to access: timed out'];

      final text = await failure();

      expect(text, contains('git fetch failed (exit code 128)'));
      expect(text, contains('timed out'));
      expect(text, contains('reach owner/app over SSH'));
    });

    test('names a repository that is not on GitHub by its url', () async {
      printed = ['err:Permission denied'];

      final text = message(
        await step(
          repository: const LeaseRepository(
            githubRepoId: 42,
            sshUrl: 'ssh://git.example.com/team/app.git',
          ),
        ).run(_input(root.path), context),
      );

      expect(text, contains('ssh://git.example.com/team/app.git'));
    });

    test('says when the cache cannot be made', () async {
      failing = 'init';
      printed = ['err:fatal: cannot mkdir'];

      expect(await failure(), contains('git could not create the cache'));
      expect(await failure(), contains('cannot mkdir'));
    });

    test('says when the origin cannot be set', () async {
      failing = 'config';

      expect(await failure(), contains('git could not set the origin'));
    });

    test('says when the commit cannot be checked out', () async {
      failing = 'worktree';
      context.handler = (command) {
        if (command.arguments.first == 'cat-file') {
          return const FakeRun(exitCode: 1);
        }
        if (command.arguments.contains('add')) {
          return const FakeRun(exitCode: 128);
        }
        return const FakeRun();
      };

      final text = await failure();

      expect(text, contains('git could not check out $_sha (exit code 128).'));
    });

    test('never runs on a tree that is not the commit', () async {
      context.handler = (command) {
        final verb = command.arguments.first;
        if (verb == 'cat-file') return const FakeRun(exitCode: 1);
        if (verb == 'rev-parse') return FakeRun(lines: ['b' * 40]);
        return const FakeRun();
      };

      final text = await failure();

      expect(text, contains('The worktree is at ${'b' * 40}, not at $_sha'));
      expect(text, contains('does not run on any other source'));
    });

    test('never runs on a tree it cannot identify', () async {
      context.handler = (command) {
        final verb = command.arguments.first;
        if (verb == 'cat-file') return const FakeRun(exitCode: 1);
        if (verb == 'rev-parse') return const FakeRun(exitCode: 128);
        return const FakeRun();
      };

      expect(await failure(), contains('an unknown commit'));
    });

    test('stops when the job is cancelled', () async {
      for (final verb in ['cat-file', 'fetch', 'add', 'rev-parse']) {
        context.handler = (command) => command.arguments.contains(verb)
            ? const FakeRun(exitCode: -15, cancelled: true)
            : (command.arguments.first == 'cat-file'
                  ? const FakeRun(exitCode: 1)
                  : const FakeRun());

        expect(await failure(), contains('cancelled'), reason: verb);
      }
    });
  });

  group('with a real repository', () {
    late String origin;
    late String commit;

    String git(List<String> arguments, String directory) {
      final result = Process.runSync('git', [
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.com',
        '-c',
        'commit.gpgsign=false',
        ...arguments,
      ], workingDirectory: directory);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    setUp(() {
      final work = p.join(root.path, 'work');
      Directory(work).createSync();
      git(['init', '--quiet', '-b', 'main'], work);
      File(p.join(work, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      git(['add', '--all'], work);
      git(['commit', '--quiet', '-m', 'one'], work);
      commit = git(['rev-parse', 'HEAD'], work);
      origin = p.join(root.path, 'origin.git');
      git(['clone', '--quiet', '--bare', work, origin], root.path);
    });

    test(
      'fetches the commit into a cache of its own and checks it out',
      () async {
        final input = _input(root.path);
        final context = ProcessContext();

        final outcome = await RemoteCheckoutStep(
          source: LeaseSource(repository: _repository, sha: commit),
          queues: queues,
          testUrl: origin,
        ).run(input, context);

        final result = (outcome as StepSucceeded<GitCheckoutResult>).result;
        expect(result.sha, commit);
        expect(git(['rev-parse', 'HEAD'], result.path), commit);
        expect(
          File(p.join(result.path, 'pubspec.yaml')).readAsStringSync(),
          'name: app\n',
        );
        expect(
          git(['rev-parse', 'refs/xpath/$commit'], input.worktree.mirror.path),
          commit,
        );
      },
    );

    test('makes a fresh worktree every time, from the cache', () async {
      final input = _input(root.path);
      Future<GitCheckoutResult> checkout() async =>
          ((await RemoteCheckoutStep(
                    source: LeaseSource(repository: _repository, sha: commit),
                    queues: queues,
                    testUrl: origin,
                  ).run(input, ProcessContext()))
                  as StepSucceeded<GitCheckoutResult>)
              .result;
      final first = await checkout();
      File(p.join(first.path, 'pubspec.yaml')).writeAsStringSync('changed');
      File(p.join(first.path, 'untracked.txt')).writeAsStringSync('x');
      // Nothing of the origin is needed any more.
      Directory(origin).deleteSync(recursive: true);

      final second = await checkout();

      expect(second.path, first.path);
      expect(
        File(p.join(second.path, 'pubspec.yaml')).readAsStringSync(),
        'name: app\n',
      );
      expect(File(p.join(second.path, 'untracked.txt')).existsSync(), isFalse);
    });

    test('fails clearly for a commit the repository does not have', () async {
      final outcome = await RemoteCheckoutStep(
        source: LeaseSource(repository: _repository, sha: 'c' * 40),
        queues: queues,
        testUrl: origin,
      ).run(_input(root.path), ProcessContext());

      expect(message(outcome), contains('GitHub has no commit cccccccccccc'));
    });

    test('fails clearly for a repository it cannot read', () async {
      final outcome = await RemoteCheckoutStep(
        source: LeaseSource(repository: _repository, sha: commit),
        queues: queues,
        testUrl: p.join(root.path, 'does-not-exist.git'),
      ).run(_input(root.path), ProcessContext());

      expect(message(outcome), contains('cannot read'));
    });
  }, tags: 'process');
}
