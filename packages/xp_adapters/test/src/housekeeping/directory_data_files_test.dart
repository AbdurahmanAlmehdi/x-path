import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

void main() {
  late Directory dataDir;
  late _RecordingGit git;
  late DirectoryDataFiles files;

  void write(String relative, int bytes) => File(p.join(dataDir.path, relative))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 1));

  bool exists(String relative) =>
      FileSystemEntity.typeSync(p.join(dataDir.path, relative)) !=
      FileSystemEntityType.notFound;

  setUp(() {
    dataDir = tempDirectory();
    git = _RecordingGit();
    files = DirectoryDataFiles(dataDir: dataDir.path, git: git);
  });

  test('has nothing when the data directory is empty', () async {
    expect(await files.logSizes(), isEmpty);
    expect(await files.worktrees(), isEmpty);
    expect(await files.mirrors(), isEmpty);
    expect(await files.flutterVersions(), isEmpty);
  });

  group('logs', () {
    test('are measured per job, nested files included', () async {
      write('logs/job_1/0-build.log', 10);
      write('logs/job_1/1-test.log', 5);
      write('logs/job_2/0-build.log', 7);
      write('logs/stray.txt', 100);

      expect(await files.logSizes(), {'job_1': 15, 'job_2': 7});
    });

    test('are deleted per job', () async {
      write('logs/job_1/0-build.log', 10);
      write('logs/job_2/0-build.log', 7);

      await files.deleteLogs('job_1');
      await files.deleteLogs('job_9');

      expect(exists('logs/job_1'), isFalse);
      expect(exists('logs/job_2'), isTrue);
    });

    test('are only found by a plain job id', () async {
      for (final id in ['', '.', '..', '../x', 'a/b', r'a\b', 'a\x00b']) {
        expect(() => files.deleteLogs(id), throwsArgumentError, reason: id);
      }
    });
  });

  group('worktrees', () {
    test('are listed by repository and job, with their size', () async {
      write('worktrees/42/job_1/a.dart', 10);
      write('worktrees/42/job_1/lib/b.dart', 5);
      write('worktrees/42/job_2/a.dart', 1);
      write('worktrees/7/job_3/a.dart', 2);
      write('worktrees/not-a-repository/job_4/a.dart', 3);
      write('worktrees/42/stray.txt', 3);

      final worktrees = await files.worktrees();

      expect(worktrees.map((w) => (w.githubRepoId, w.name, w.bytes)), [
        (42, 'job_1', 15),
        (42, 'job_2', 1),
        (7, 'job_3', 2),
      ]);
      expect(worktrees.first.path, p.join(dataDir.path, 'worktrees/42/job_1'));
    });

    test('are forgotten by their mirror before they go', () async {
      write('worktrees/42/job_1/a.dart', 1);
      write('worktrees/42/job_2/a.dart', 1);
      final worktrees = await files.worktrees();

      await files.deleteWorktree(worktrees.first);

      expect(git.removed.single.path, worktrees.first.path);
      expect(
        git.removed.single.mirror,
        GitMirror(
          githubRepoId: 42,
          path: p.join(dataDir.path, 'mirrors', '42.git'),
        ),
      );
      // The fake git removed nothing; the folder is still there.
      expect(exists('worktrees/42/job_1'), isTrue);
    });

    test('the folder of a repository with none left goes too', () async {
      write('worktrees/42/job_1/a.dart', 1);
      git.onRemove = (worktree) =>
          Directory(worktree.path).deleteSync(recursive: true);

      await files.deleteWorktree((await files.worktrees()).single);

      expect(exists('worktrees/42'), isFalse);
    });

    test('the folder of a repository with others left stays', () async {
      write('worktrees/42/job_1/a.dart', 1);
      write('worktrees/42/job_2/a.dart', 1);
      git.onRemove = (worktree) =>
          Directory(worktree.path).deleteSync(recursive: true);

      await files.deleteWorktree((await files.worktrees()).first);

      expect(exists('worktrees/42/job_2'), isTrue);
    });
  });

  group('mirrors', () {
    test('are the folders named for a repository id', () async {
      write('mirrors/42.git/HEAD', 20);
      write('mirrors/42.git/objects/pack/x.pack', 100);
      write('mirrors/7.git/HEAD', 3);
      write('mirrors/readme.txt', 1);
      Directory(p.join(dataDir.path, 'mirrors', 'x.git')).createSync();

      final mirrors = await files.mirrors();

      expect(mirrors.map((m) => (m.githubRepoId, m.bytes)), [
        (42, 120),
        (7, 3),
      ]);
    });

    test('go with what is left of their worktrees', () async {
      write('mirrors/42.git/HEAD', 1);
      write('worktrees/42/job_1/a.dart', 1);
      write('worktrees/7/job_2/a.dart', 1);
      write('mirrors/7.git/HEAD', 1);

      await files.deleteMirror((await files.mirrors()).first);

      expect(exists('mirrors/42.git'), isFalse);
      expect(exists('worktrees/42'), isFalse);
      expect(exists('mirrors/7.git'), isTrue);
      expect(exists('worktrees/7'), isTrue);
    });

    test('deleting one that is gone does nothing', () async {
      await files.deleteMirror(
        const MirrorDirectory(githubRepoId: 9, path: '/nowhere', bytes: 0),
      );
    });
  });

  group('Flutter SDKs', () {
    test('are the folders of the cache, but not installs under way', () async {
      write('toolchains/flutter/3.47.6/bin/flutter', 50);
      write('toolchains/flutter/3.35.4/bin/flutter', 20);
      write('toolchains/flutter/.install-3.50.0-x/bin/flutter', 99);
      write('toolchains/flutter/readme.txt', 1);

      final sdks = await files.flutterVersions();

      expect(sdks.map((s) => (s.version, s.bytes)), [
        ('3.35.4', 20),
        ('3.47.6', 50),
      ]);
    });

    test('are deleted by version', () async {
      write('toolchains/flutter/3.47.6/bin/flutter', 50);
      write('toolchains/flutter/3.35.4/bin/flutter', 20);

      await files.deleteFlutterVersion(
        (await files.flutterVersions()).firstWhere(
          (s) => s.version == '3.47.6',
        ),
      );

      expect(exists('toolchains/flutter/3.47.6'), isFalse);
      expect(exists('toolchains/flutter/3.35.4'), isTrue);
    });

    test('are only found by a plain version', () {
      expect(
        () => files.deleteFlutterVersion(
          const FlutterDirectory(version: '../x', path: '/x', bytes: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  test('a link is not followed when measuring', () async {
    write('logs/job_1/a.log', 10);
    final outside = tempDirectory();
    File(p.join(outside.path, 'big.bin'))
        .writeAsBytesSync(List.filled(1000, 1));
    Link(p.join(dataDir.path, 'logs', 'job_1', 'link'))
        .createSync(outside.path);

    expect(await files.logSizes(), {'job_1': 10});
  });
}

class _RecordingGit implements GitService {
  final removed = <GitWorktree>[];
  void Function(GitWorktree worktree)? onRemove;

  @override
  Future<void> removeWorktree(GitWorktree worktree) async {
    removed.add(worktree);
    onRemove?.call(worktree);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
