import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_startup.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late Directory directory;
  late RunnerPaths paths;
  late SecretArea area;
  late PgidJournal journal;
  late FakeProcessGroupControl control;
  late FakeProcessRunner runner;

  Future<StartupReport> clean({bool isMacOS = false}) => cleanUpAfterCrash(
    paths: paths,
    secrets: area,
    journal: journal,
    killer: ProcessGroupKiller(control: control, delay: (_) async {}),
    runner: runner,
    isMacOS: isMacOS,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_startup_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = RunnerPaths(directory.path);
    area = SecretArea(
      SecretLocations(
        active: paths.fallbackSecrets,
        all: [paths.fallbackSecrets],
      ),
    );
    journal = PgidJournal(paths.state);
    control = FakeProcessGroupControl(alive: [4001]);
    runner = FakeProcessRunner((call) => const ProcessOutput(exitCode: 0));
  });

  test('has nothing to clean after a runner that ended properly', () async {
    final report = await clean();

    expect(report.isClean, isTrue);
    expect(report.describe(), 'Nothing was left by an earlier run.');
    expect(Directory(paths.fallbackSecrets).existsSync(), isTrue);
  });

  test(
    'stops the processes, wipes the secrets and removes the job folders',
    () async {
      await journal.track('job_1', 1, 4001);
      File(p.join(paths.fallbackSecrets, 'job_1', 'delivered-abc'))
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');
      File(p.join(paths.jobDirectory('job_1'), 'app.apk'))
        ..createSync(recursive: true)
        ..writeAsStringSync('apk');
      File(p.join(paths.source, 'worktrees', '42', 'job_1', 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: app');
      Directory(p.join(paths.source, 'mirrors', '42.git'))
          .createSync(recursive: true);
      final restarted = PgidJournal(paths.state);

      final report = await cleanUpAfterCrash(
        paths: paths,
        secrets: area,
        journal: restarted,
        killer: ProcessGroupKiller(control: control, delay: (_) async {}),
        runner: runner,
        isMacOS: false,
      );

      expect(report.processGroups, 1);
      expect(report.secretFolders, 1);
      expect(report.workFolders, 2);
      expect(report.isClean, isFalse);
      expect(
        report.describe(),
        'Cleaned up after an earlier run: stopped 1 process groups, deleted 1 '
        'secret folders, 0 temporary keychains and 2 job folders.',
      );
      expect(control.alive, isEmpty);
      expect(Directory(paths.fallbackSecrets).listSync(), isEmpty);
      expect(Directory(paths.jobs).listSync(), isEmpty);
      expect(Directory(p.join(paths.source, 'worktrees')).listSync(), isEmpty);
      // The cache stays; git forgets the worktrees that are gone.
      expect(
        Directory(p.join(paths.source, 'mirrors', '42.git')).existsSync(),
        isTrue,
      );
      expect(runner.calls.map((c) => c.arguments.join(' ')), [
        'worktree prune',
      ]);
      expect(runner.calls.single.workingDirectory, endsWith('42.git'));
    },
  );

  test('removes the temporary keychains on a Mac', () async {
    File(p.join(paths.keychains, 'job_1.keychain-db'))
      ..createSync(recursive: true)
      ..writeAsStringSync('keychain');

    final report = await clean(isMacOS: true);

    expect(report.keychains, 1);
    expect(Directory(paths.keychains).listSync(), isEmpty);
    expect(
      runner.calls.map((c) => c.stdin).join('\n'),
      contains('delete-keychain'),
    );
  });

  test('does not look for keychains elsewhere', () async {
    File(p.join(paths.keychains, 'job_1.keychain-db'))
      ..createSync(recursive: true)
      ..writeAsStringSync('keychain');

    final report = await clean();

    expect(report.keychains, 0);
    expect(runner.calls, isEmpty);
  });
}
