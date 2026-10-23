@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/git_fixture.dart';
import '../../helpers/memory_secret_store.dart';

void main() {
  late GitFixture fixture;
  late Directory dataDir;
  late CliGitService service;
  late GitMirror mirror;
  late String first;
  late String second;

  setUp(() async {
    fixture = GitFixture.create();
    dataDir = Directory.systemTemp.createTempSync('xp_git_data_');
    first = fixture.commit('a.txt', 'one');
    second = fixture.commit('b.txt', 'two');
    fixture.push('main');
    service = CliGitService(
      runner: const IoProcessRunner(),
      secrets: MemorySecretStore(),
      dataDir: dataDir.path,
    );
    mirror = await service.ensureMirror(
      key: '42',
      remoteUrl: fixture.originUrl,
    );
    await service.fetch(mirror);
  });

  tearDown(() {
    fixture.dispose();
    dataDir.deleteSync(recursive: true);
  });

  String inMirror(List<String> arguments) =>
      fixture.git(arguments, cwd: mirror.path);

  group('ensureMirror', () {
    test('creates a bare repository keyed by the source key', () {
      expect(mirror.key, '42');
      expect(mirror.path, p.join(dataDir.path, 'mirrors', '42.git'));
      expect(inMirror(['rev-parse', '--is-bare-repository']), 'true');
      expect(inMirror(['remote', 'get-url', 'origin']), fixture.originUrl);
    });

    test('is idempotent', () async {
      final again = await service.ensureMirror(
        key: '42',
        remoteUrl: fixture.originUrl,
      );

      expect(again, mirror);
      expect(inMirror(['rev-parse', 'refs/remotes/origin/main']), second);
    });

    test('follows a renamed remote by updating origin', () async {
      await service.ensureMirror(
        key: '42',
        remoteUrl: 'https://github.com/acme/renamed.git',
      );

      expect(
        inMirror(['remote', 'get-url', 'origin']),
        'https://github.com/acme/renamed.git',
      );
      expect(inMirror(['rev-parse', 'refs/remotes/origin/main']), second);
    });

    test('keys the mirror of a project on another host by its h key', () async {
      final key = GitRemote.parse(fixture.originUrl)!.sourceKey;

      final other = await service.ensureMirror(
        key: key,
        remoteUrl: fixture.originUrl,
      );
      await service.fetch(other);

      expect(key, matches(RegExp(r'^h[0-9a-f]{16}$')));
      expect(other.path, p.join(dataDir.path, 'mirrors', '$key.git'));
      expect(await service.resolveRef(other, 'main'), second);
      expect(mirror.path, p.join(dataDir.path, 'mirrors', '42.git'));
    });

    test('refuses a key that is not a source key', () {
      for (final key in ['', '../x', 'h123', 'H0123456789ABCDEF', '-1']) {
        expect(
          service.ensureMirror(key: key, remoteUrl: fixture.originUrl),
          throwsArgumentError,
          reason: key,
        );
      }
    });

    test('refuses a URL that looks like an option', () {
      expect(
        service.ensureMirror(key: '1', remoteUrl: '--upload-pack=x'),
        throwsArgumentError,
      );
      expect(
        service.ensureMirror(key: '1', remoteUrl: ''),
        throwsArgumentError,
      );
    });
  });

  group('fetch', () {
    test('brings new branches and tags and prunes deleted branches', () async {
      fixture
        ..git(['branch', 'topic', first])
        ..git(['push', '--quiet', 'origin', 'topic'])
        ..git(['tag', 'v0.1.0', first])
        ..git(['push', '--quiet', 'origin', 'v0.1.0']);
      await service.fetch(mirror);
      expect(inMirror(['rev-parse', 'refs/remotes/origin/topic']), first);
      expect(inMirror(['rev-parse', 'refs/tags/v0.1.0^{commit}']), first);

      fixture.git(['push', '--quiet', 'origin', '--delete', 'topic']);
      await service.fetch(mirror);

      expect(await service.resolveRef(mirror, 'main'), second);
      expect(
        service.resolveRef(mirror, 'topic'),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });

    test("fails with git's message when the remote is gone", () async {
      await service.ensureMirror(
        key: '42',
        remoteUrl: Uri.file(p.join(fixture.root.path, 'gone.git')).toString(),
      );

      await expectLater(
        service.fetch(mirror),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            startsWith('git fetch failed'),
          ),
        ),
      );
    });
  });

  group('resolveRef', () {
    test('resolves branches, tags and full and abbreviated SHAs', () async {
      fixture
        ..git(['tag', '-a', '-m', 'v', 'v1', first])
        ..git(['push', '--quiet', 'origin', 'v1']);
      await service.fetch(mirror);

      expect(await service.resolveRef(mirror, 'main'), second);
      expect(await service.resolveRef(mirror, 'v1'), first);
      expect(await service.resolveRef(mirror, first), first);
      expect(await service.resolveRef(mirror, first.substring(0, 8)), first);
    });

    test('prefers a local branch over the remote one', () async {
      await service.upsertBranch(mirror, name: 'main', sha: second);
      fixture
        ..commit('c.txt', 'three')
        ..push('main');
      await service.fetch(mirror);

      expect(await service.resolveRef(mirror, 'main'), second);
    });

    test('throws for something that is not a commit', () {
      expect(
        service.resolveRef(mirror, 'nope'),
        throwsA(
          isA<GitRefNotFoundException>().having((e) => e.ref, 'ref', 'nope'),
        ),
      );
      expect(
        service.resolveRef(mirror, '0' * 40),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });
  });

  group('worktrees', () {
    test('are isolated from each other, the mirror and the source', () async {
      final a = await service.createWorktree(mirror, name: 'job-a', sha: first);
      final b = await service.createWorktree(
        mirror,
        name: 'job-b',
        sha: 'main',
      );

      expect(a.sha, first);
      expect(b.sha, second);
      expect(a.path, isNot(b.path));
      expect(File(p.join(a.path, 'a.txt')).readAsStringSync(), 'one');
      expect(File(p.join(a.path, 'b.txt')).existsSync(), isFalse);
      expect(File(p.join(b.path, 'b.txt')).readAsStringSync(), 'two');
      expect(
        fixture.git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd: a.path),
        'HEAD',
        reason: 'the head is detached',
      );

      File(p.join(a.path, 'scratch.txt')).writeAsStringSync('only in a');
      File(p.join(a.path, 'a.txt')).writeAsStringSync('changed in a');

      expect(File(p.join(b.path, 'scratch.txt')).existsSync(), isFalse);
      expect(File(p.join(b.path, 'a.txt')).readAsStringSync(), 'one');
      expect(File(p.join(mirror.path, 'scratch.txt')).existsSync(), isFalse);
      expect(inMirror(['show', '$first:a.txt']), 'one');
      expect(File(p.join(fixture.seed, 'scratch.txt')).existsSync(), isFalse);
      expect(File(p.join(fixture.seed, 'a.txt')).readAsStringSync(), 'one');
    });

    test('are where the engine says they will be, before they exist', () async {
      final path = CliGitService.worktreePath(
        dataDir.path,
        mirror,
        'job-before',
      );

      final worktree = await service.createWorktree(
        mirror,
        name: 'job-before',
        sha: first,
      );

      expect(worktree.path, path);
      expect(path, p.join(dataDir.path, 'worktrees', '42', 'job-before'));
    });

    test('are replaced when the name is reused', () async {
      final old = await service.createWorktree(mirror, name: 'job', sha: first);
      File(p.join(old.path, 'leftover.txt')).writeAsStringSync('stale');

      final fresh = await service.createWorktree(
        mirror,
        name: 'job',
        sha: second,
      );

      expect(fresh.path, old.path);
      expect(File(p.join(fresh.path, 'leftover.txt')).existsSync(), isFalse);
      expect(File(p.join(fresh.path, 'b.txt')).existsSync(), isTrue);
    });

    test('are replaced when only a bare directory is left', () async {
      final leftover = Directory(
        p.join(dataDir.path, 'worktrees', '42', 'crashed'),
      )..createSync(recursive: true);
      File(p.join(leftover.path, 'x')).writeAsStringSync('x');

      final worktree = await service.createWorktree(
        mirror,
        name: 'crashed',
        sha: first,
      );

      expect(File(p.join(worktree.path, 'x')).existsSync(), isFalse);
      expect(File(p.join(worktree.path, 'a.txt')).existsSync(), isTrue);
    });

    test('are removed with their directory and registration', () async {
      final worktree = await service.createWorktree(
        mirror,
        name: 'job',
        sha: first,
      );

      await service.removeWorktree(worktree);
      await service.removeWorktree(worktree);

      expect(Directory(worktree.path).existsSync(), isFalse);
      expect(inMirror(['worktree', 'list']), isNot(contains('job')));
    });

    test('refuse an unknown commit and an unsafe name', () async {
      await expectLater(
        service.createWorktree(mirror, name: 'job', sha: '1' * 40),
        throwsA(isA<GitRefNotFoundException>()),
      );
      for (final name in ['', '../escape', '.hidden', 'a/b', '-x']) {
        await expectLater(
          service.createWorktree(mirror, name: name, sha: first),
          throwsArgumentError,
          reason: name,
        );
      }
    });
  });

  group('createTag', () {
    test('creates an annotated tag by the engine identity', () async {
      final outcome = await service.createTag(
        mirror,
        name: 'v1.0.0+7',
        sha: first,
        message: 'Release 1.0.0 (7)',
      );

      expect(outcome, TagOutcome.created);
      expect(inMirror(['cat-file', '-t', 'refs/tags/v1.0.0+7']), 'tag');
      expect(inMirror(['rev-parse', 'refs/tags/v1.0.0+7^{commit}']), first);
      expect(
        inMirror(['for-each-ref', '--format=%(taggername)', 'refs/tags']),
        'XPath',
      );
    });

    test('reuses a tag that is already on the same commit', () async {
      await service.createTag(mirror, name: 'v1', sha: first, message: 'm');
      final tagObject = inMirror(['rev-parse', 'refs/tags/v1']);

      final outcome = await service.createTag(
        mirror,
        name: 'v1',
        sha: first,
        message: 'another message',
      );

      expect(outcome, TagOutcome.reused);
      expect(inMirror(['rev-parse', 'refs/tags/v1']), tagObject);
    });

    test('reuses a lightweight tag fetched from the remote', () async {
      fixture
        ..git(['tag', 'v2', second])
        ..git(['push', '--quiet', 'origin', 'v2']);
      await service.fetch(mirror);

      final outcome = await service.createTag(
        mirror,
        name: 'v2',
        sha: 'main',
        message: 'm',
      );

      expect(outcome, TagOutcome.reused);
    });

    test('refuses a tag that is on another commit and leaves it', () async {
      await service.createTag(mirror, name: 'v1', sha: first, message: 'm');

      await expectLater(
        service.createTag(mirror, name: 'v1', sha: second, message: 'm'),
        throwsA(
          isA<GitTagConflictException>()
              .having((e) => e.tag, 'tag', 'v1')
              .having((e) => e.existingSha, 'existing', first)
              .having((e) => e.requestedSha, 'requested', second),
        ),
      );
      expect(inMirror(['rev-parse', 'refs/tags/v1^{commit}']), first);
    });

    test('refuses a tag moved by the remote since it was made', () async {
      fixture
        ..git(['tag', 'v3', first])
        ..git(['push', '--quiet', 'origin', 'v3']);
      await service.fetch(mirror);

      await expectLater(
        service.createTag(mirror, name: 'v3', sha: second, message: 'm'),
        throwsA(isA<GitTagConflictException>()),
      );
    });

    test('rejects bad names, blank messages and unknown commits', () async {
      for (final name in ['', '-x', 'a b', 'a..b', 'v1.lock']) {
        await expectLater(
          service.createTag(mirror, name: name, sha: first, message: 'm'),
          throwsArgumentError,
          reason: name,
        );
      }
      await expectLater(
        service.createTag(mirror, name: 'v1', sha: first, message: '  '),
        throwsArgumentError,
      );
      await expectLater(
        service.createTag(mirror, name: 'v1', sha: '2' * 40, message: 'm'),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });
  });

  group('upsertBranch', () {
    test('creates a branch, then leaves it alone on the same commit', () async {
      expect(
        await service.upsertBranch(mirror, name: 'release/1.0', sha: first),
        BranchOutcome.created,
      );
      expect(
        await service.upsertBranch(mirror, name: 'release/1.0', sha: first),
        BranchOutcome.unchanged,
      );
      expect(inMirror(['rev-parse', 'refs/heads/release/1.0']), first);
    });

    test('moves a branch forward to a descendant', () async {
      await service.upsertBranch(mirror, name: 'release/1.0', sha: first);

      final outcome = await service.upsertBranch(
        mirror,
        name: 'release/1.0',
        sha: second,
      );

      expect(outcome, BranchOutcome.updated);
      expect(inMirror(['rev-parse', 'refs/heads/release/1.0']), second);
    });

    test('refuses to move a branch sideways or back, without force', () async {
      fixture.git(['checkout', '--quiet', '-b', 'side', first]);
      final side = fixture.commit('side.txt', 'side');
      fixture.push('side');
      await service.fetch(mirror);
      await service.upsertBranch(mirror, name: 'release/1.0', sha: second);

      await expectLater(
        service.upsertBranch(mirror, name: 'release/1.0', sha: side),
        throwsA(
          isA<GitBranchConflictException>()
              .having((e) => e.branch, 'branch', 'release/1.0')
              .having((e) => e.currentSha, 'current', second)
              .having((e) => e.requestedSha, 'requested', side),
        ),
      );
      await expectLater(
        service.upsertBranch(mirror, name: 'release/1.0', sha: first),
        throwsA(isA<GitBranchConflictException>()),
      );
      expect(inMirror(['rev-parse', 'refs/heads/release/1.0']), second);
    });

    test('takes the remote branch as the tip when there is no local', () async {
      fixture.git(['checkout', '--quiet', '-b', 'side', first]);
      final side = fixture.commit('side.txt', 'side');

      // `main` exists on the remote at `second`; `side` does not descend.
      fixture.push('side');
      await service.fetch(mirror);
      await expectLater(
        service.upsertBranch(mirror, name: 'main', sha: side),
        throwsA(isA<GitBranchConflictException>()),
      );

      fixture.git(['checkout', '--quiet', 'main']);
      final third = fixture.commit('c.txt', 'three');
      fixture.push('main');
      await service.fetch(mirror);
      expect(
        await service.upsertBranch(mirror, name: 'main', sha: third),
        BranchOutcome.created,
      );
      expect(inMirror(['rev-parse', 'refs/heads/main']), third);
    });

    test('rejects bad names and unknown commits', () async {
      for (final name in ['', '-x', 'a b', 'a..b']) {
        await expectLater(
          service.upsertBranch(mirror, name: name, sha: first),
          throwsArgumentError,
          reason: name,
        );
      }
      await expectLater(
        service.upsertBranch(mirror, name: 'x', sha: '3' * 40),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });
  });

  group('push', () {
    test('pushes a new branch and a new tag to the origin', () async {
      await service.upsertBranch(mirror, name: 'release/1.0', sha: second);
      await service.createTag(
        mirror,
        name: 'v1.0.0+1',
        sha: second,
        message: 'Release',
      );

      await service.push(
        mirror,
        refspecs: [
          GitRefspecs.branch('release/1.0'),
          GitRefspecs.tag('v1.0.0+1'),
        ],
      );

      expect(fixture.originRef('refs/heads/release/1.0'), second);
      expect(fixture.originRef('refs/tags/v1.0.0+1'), second);
    });

    test('pushing what the origin already has is a no-op', () async {
      await service.createTag(mirror, name: 'v1', sha: first, message: 'm');
      await service.push(mirror, refspecs: [GitRefspecs.tag('v1')]);

      await service.push(mirror, refspecs: [GitRefspecs.tag('v1')]);

      expect(fixture.originRef('refs/tags/v1'), first);
    });

    test('is rejected when the branch is not a fast-forward', () async {
      await service.upsertBranch(mirror, name: 'release/1.0', sha: first);
      fixture
        ..git(['checkout', '--quiet', '-b', 'release/1.0', second])
        ..push('release/1.0');

      await expectLater(
        service.push(mirror, refspecs: [GitRefspecs.branch('release/1.0')]),
        throwsA(isA<GitPushRejectedException>()),
      );
      expect(fixture.originRef('refs/heads/release/1.0'), second);
    });

    test('is rejected when the tag exists on another commit', () async {
      fixture
        ..git(['tag', 'v9', first])
        ..git(['push', '--quiet', 'origin', 'v9']);
      // The mirror has not fetched, so it does not know the tag.
      await service.createTag(mirror, name: 'v9', sha: second, message: 'm');

      await expectLater(
        service.push(mirror, refspecs: [GitRefspecs.tag('v9')]),
        throwsA(isA<GitPushRejectedException>()),
      );
      expect(fixture.originRef('refs/tags/v9'), first);
    });

    test("fails with git's message when the origin is unreachable", () async {
      await service.upsertBranch(mirror, name: 'b', sha: first);
      await service.ensureMirror(
        key: '42',
        remoteUrl: Uri.file(p.join(fixture.root.path, 'gone.git')).toString(),
      );

      await expectLater(
        service.push(mirror, refspecs: [GitRefspecs.branch('b')]),
        throwsA(
          isA<GitException>()
              .having((e) => e, 'type', isNot(isA<GitPushRejectedException>()))
              .having((e) => e.message, 'message', startsWith('git push')),
        ),
      );
    });

    test('refuses forced, wildcard, deleting and malformed refspecs', () async {
      for (final refspec in [
        '+refs/heads/main:refs/heads/main',
        'refs/heads/*:refs/heads/*',
        ':refs/heads/main',
        'main:main',
        '--force',
        '--delete',
        'refs/heads/main',
        'refs/heads/a b:refs/heads/a b',
      ]) {
        await expectLater(
          service.push(mirror, refspecs: [refspec]),
          throwsArgumentError,
          reason: refspec,
        );
      }
      await expectLater(
        service.push(mirror, refspecs: []),
        throwsArgumentError,
      );
      expect(fixture.originRef('refs/heads/main'), second);
    });
  });

  group('listTags', () {
    test('is empty for a mirror without tags', () async {
      expect(await service.listTags(mirror), isEmpty);
    });

    test('names the commit of annotated and lightweight tags', () async {
      fixture
        ..git(['tag', 'v5.4.1+3283', second])
        ..git(['tag', '-a', '-m', 'm', 'mobile/prod/v1.0.0+7', first])
        ..git(['push', '--quiet', 'origin', '--tags']);
      await service.fetch(mirror);
      await service.createTag(
        mirror,
        name: 'v5.4.0+3282',
        sha: first,
        message: 'Release',
      );

      expect(await service.listTags(mirror), [
        GitTagInfo(name: 'mobile/prod/v1.0.0+7', commit: first),
        GitTagInfo(name: 'v5.4.0+3282', commit: first),
        GitTagInfo(name: 'v5.4.1+3283', commit: second),
      ]);
    });
  });

  group('changedFiles', () {
    test('lists what differs between two commits, sorted', () async {
      fixture.commit('lib/z.dart', 'z');
      final third = fixture.commit('android/app/build.gradle', 'g');
      fixture.push('main');
      await service.fetch(mirror);

      expect(await service.changedFiles(mirror, from: first, to: third), [
        'android/app/build.gradle',
        'b.txt',
        'lib/z.dart',
      ]);
      expect(
        await service.changedFiles(mirror, from: first, to: first),
        isEmpty,
      );
    });

    test(
      'resolves tags and branches, and names both sides of a rename',
      () async {
        await service.createTag(mirror, name: 'v1', sha: second, message: 'm');
        fixture
          ..git(['mv', 'a.txt', 'c.txt'])
          ..git(['commit', '--quiet', '-m', 'rename'])
          ..push('main');
        await service.fetch(mirror);
        await service.createTag(
          mirror,
          name: 'v1',
          sha: second,
          message: 'again',
        );

        expect(await service.changedFiles(mirror, from: 'v1', to: 'main'), [
          'a.txt',
          'c.txt',
        ]);
      },
    );

    test('reads a name with spaces and quotes as it is', () async {
      final odd = fixture.commit('lib/a "b" é.dart', 'x');
      fixture.push('main');
      await service.fetch(mirror);

      expect(await service.changedFiles(mirror, from: second, to: odd), [
        'lib/a "b" é.dart',
      ]);
    });

    test('fails for a commit that does not exist', () {
      expect(
        service.changedFiles(mirror, from: 'v404', to: second),
        throwsA(isA<GitRefNotFoundException>()),
      );
      expect(
        service.changedFiles(mirror, from: first, to: 'nope'),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });
  });

  group('commitsBetween', () {
    test(
      'lists the commits after a tag, newest first, with their bodies',
      () async {
        fixture
          ..git(['tag', '-a', '-m', 'v', 'v1', second])
          ..git(['push', '--quiet', 'origin', 'v1']);
        final third = fixture.commit(
          'c.txt',
          'c',
          message:
              'feat(ui): add dark mode\n\nBody line.\n\nBREAKING CHANGE: x',
        );
        final fourth = fixture.commit(
          'd.txt',
          'd',
          message: 'fix: handle \u00e9',
        );
        fixture.push('main');
        await service.fetch(mirror);

        final commits = await service.commitsBetween(
          mirror,
          from: 'v1',
          to: 'main',
        );

        expect(commits, [
          GitCommit(sha: fourth, subject: 'fix: handle \u00e9'),
          GitCommit(
            sha: third,
            subject: 'feat(ui): add dark mode',
            body: 'Body line.\n\nBREAKING CHANGE: x',
          ),
        ]);
      },
    );

    test(
      'leaves out merge commits but keeps the commits they merged',
      () async {
        fixture
          ..git(['checkout', '--quiet', '-b', 'topic'])
          ..commit('t.txt', 't', message: 'feat: on a branch')
          ..git(['checkout', '--quiet', 'main']);
        final onMain = fixture.commit('m.txt', 'm', message: 'fix: on main');
        fixture
          ..git(['merge', '--quiet', '--no-ff', '-m', 'Merge topic', 'topic'])
          ..push('main');
        await service.fetch(mirror);

        final commits = await service.commitsBetween(
          mirror,
          from: second,
          to: 'main',
        );

        expect(commits.map((c) => c.subject), [
          'fix: on main',
          'feat: on a branch',
        ]);
        expect(commits.map((c) => c.sha), contains(onMain));
      },
    );

    test('lists nothing when the two are the same commit', () async {
      expect(
        await service.commitsBetween(mirror, from: second, to: second),
        isEmpty,
      );
    });

    test('without a start lists the latest commits up to the limit', () async {
      expect(
        (await service.commitsBetween(mirror, to: second)).map((c) => c.sha),
        [second, first],
      );
      expect(
        (await service.commitsBetween(
          mirror,
          to: second,
          limit: 1,
        )).map((c) => c.sha),
        [second],
      );
    });

    test('refuses a limit below 1', () {
      expect(
        service.commitsBetween(mirror, to: second, limit: 0),
        throwsArgumentError,
      );
    });

    test('fails for a ref that does not exist', () {
      expect(
        service.commitsBetween(mirror, from: 'v404', to: second),
        throwsA(isA<GitRefNotFoundException>()),
      );
      expect(
        service.commitsBetween(mirror, to: 'nope'),
        throwsA(isA<GitRefNotFoundException>()),
      );
    });
  });

  group('status and commit', () {
    late GitWorktree worktree;

    String inWorktree(List<String> arguments) =>
        fixture.git(arguments, cwd: worktree.path);

    void write(String path, String content) {
      final file = File(p.join(worktree.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    setUp(() async {
      worktree = await service.createWorktree(mirror, name: 'job', sha: second);
    });

    test('a fresh worktree is clean and on its commit', () async {
      final status = await service.status(worktree);

      expect(status.headSha, second);
      expect(status.isClean, isTrue);
    });

    test('reports changed, deleted and untracked files', () async {
      write('a.txt', 'changed');
      File(p.join(worktree.path, 'b.txt')).deleteSync();
      write('lib/debug/flags.dart', 'untracked');
      write('lib/other.dart', 'untracked');
      write('notes with space.txt', 'untracked');
      write('staged.txt', 's');
      inWorktree(['add', 'staged.txt']);

      final status = await service.status(worktree);

      expect(status.changed, ['a.txt', 'b.txt', 'staged.txt']);
      expect(status.untracked, [
        'lib/debug/flags.dart',
        'lib/other.dart',
        'notes with space.txt',
      ]);
      expect(status.isClean, isFalse);
    });

    test('does not report ignored files', () async {
      fixture
        ..commit('.gitignore', 'build/\n*.log\n')
        ..push('main');
      await service.fetch(mirror);
      final ignoring = await service.createWorktree(
        mirror,
        name: 'ignoring',
        sha: 'main',
      );
      Directory(p.join(ignoring.path, 'build')).createSync();
      File(p.join(ignoring.path, 'build', 'out.bin')).writeAsStringSync('x');
      File(p.join(ignoring.path, 'run.log')).writeAsStringSync('x');

      final status = await service.status(ignoring);

      expect(status.untracked, isEmpty);
      expect(status.changed, isEmpty);
    });

    test('is a GitException where there is no repository', () async {
      final empty = Directory.systemTemp.createTempSync('xp_not_git_');
      addTearDown(() => empty.deleteSync(recursive: true));

      await expectLater(
        service.status(
          GitWorktree(mirror: mirror, path: empty.path, sha: first),
        ),
        throwsA(isA<GitException>()),
      );
      await expectLater(
        service.status(
          GitWorktree(
            mirror: mirror,
            path: p.join(empty.path, 'gone'),
            sha: first,
          ),
        ),
        throwsA(isA<GitException>()),
      );
    });

    test(
      'commits the paths as the engine identity and moves the head',
      () async {
        write('pubspec.yaml', 'version: 1.0.0+1\n');
        write('ios/Runner/Info.plist', '<plist/>');

        final result = await service.commit(
          worktree,
          message: 'chore(release): 1.0.0+1',
          paths: ['pubspec.yaml', 'ios/Runner/Info.plist'],
        );

        expect(result.created, isTrue);
        expect(result.sha, isNot(second));
        expect(result.sha, inWorktree(['rev-parse', 'HEAD']));
        expect(result.tree, inWorktree(['rev-parse', 'HEAD^{tree}']));
        expect(inWorktree(['rev-parse', 'HEAD^']), second);
        expect(
          inWorktree(['log', '-1', '--format=%an <%ae>|%cn|%s']),
          'XPath <xpath@localhost>|XPath|chore(release): 1.0.0+1',
        );
        expect(
          inWorktree(['show', '--name-only', '--format=', 'HEAD']).split('\n')
            ..sort(),
          ['ios/Runner/Info.plist', 'pubspec.yaml'],
        );
        expect((await service.status(worktree)).headSha, result.sha);
        expect((await service.status(worktree)).isClean, isTrue);
      },
    );

    test('leaves other changes out of the commit', () async {
      write('pubspec.yaml', 'version: 1.0.0+1\n');
      write('a.txt', 'edited by hand');
      write('scratch.txt', 'untracked');

      await service.commit(worktree, message: 'm', paths: ['pubspec.yaml']);

      final status = await service.status(worktree);
      expect(status.changed, ['a.txt']);
      expect(status.untracked, ['scratch.txt']);
      expect(inWorktree(['show', 'HEAD:a.txt']), 'one');
    });

    test('commits nothing when the paths are as the head has them', () async {
      write('pubspec.yaml', 'v1');
      final made = await service.commit(
        worktree,
        message: 'bump',
        paths: ['pubspec.yaml'],
      );

      final again = await service.commit(
        worktree,
        message: 'bump',
        paths: ['pubspec.yaml', 'a.txt'],
      );

      expect(again.created, isFalse);
      expect(again.sha, made.sha);
      expect(again.tree, made.tree);
      expect(inWorktree(['rev-list', '--count', 'HEAD']), '3');
    });

    test('makes a commit that a release branch can point at', () async {
      write('pubspec.yaml', 'v1');
      final made = await service.commit(
        worktree,
        message: 'bump',
        paths: ['pubspec.yaml'],
      );

      final outcome = await service.upsertBranch(
        mirror,
        name: 'release/1.0.0',
        sha: made.sha,
      );

      expect(outcome, BranchOutcome.created);
      expect(inMirror(['rev-parse', 'refs/heads/release/1.0.0']), made.sha);
      expect(fixture.originRef('refs/heads/release/1.0.0'), isNull);
    });

    test(
      'refuses arguments that could be options or leave the worktree',
      () async {
        write('pubspec.yaml', 'v1');
        for (final path in [
          '',
          '-x',
          '/etc/passwd',
          '../outside',
          'a/../../b',
        ]) {
          await expectLater(
            service.commit(worktree, message: 'm', paths: [path]),
            throwsArgumentError,
            reason: path,
          );
        }
        await expectLater(
          service.commit(worktree, message: '  ', paths: ['pubspec.yaml']),
          throwsArgumentError,
        );
        await expectLater(
          service.commit(worktree, message: 'm', paths: []),
          throwsArgumentError,
        );
        expect((await service.status(worktree)).headSha, second);
      },
    );

    test("fails with git's message for a path that does not exist", () async {
      await expectLater(
        service.commit(worktree, message: 'm', paths: ['nope.txt']),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            startsWith('git add failed'),
          ),
        ),
      );
    });

    test('is a GitException where there is no repository', () async {
      final empty = Directory.systemTemp.createTempSync('xp_not_git_');
      addTearDown(() => empty.deleteSync(recursive: true));
      File(p.join(empty.path, 'x')).writeAsStringSync('x');

      await expectLater(
        service.commit(
          GitWorktree(mirror: mirror, path: empty.path, sha: first),
          message: 'm',
          paths: ['x'],
        ),
        throwsA(isA<GitException>()),
      );
    });
  });
}
