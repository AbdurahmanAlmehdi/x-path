@Tags(['process'])
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/update/runner_updater.dart';
import 'package:xp/src/runner/update/update_journal.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart' hide ArtifactDownload;

import '../../../helpers/bundle_fixtures.dart';

void main() {
  late Directory directory;
  late RunnerPaths paths;
  late List<String> said;
  // The bundle that runs now: version 1.0.0.
  late Directory running;
  late List<int> next;

  RunnerUpdater updater({
    BundleFetcher? fetch,
    String version = '1.0.0',
    String? bundle,
    ProcessRunner runner = const IoProcessRunner(),
  }) => RunnerUpdater(
    paths: paths,
    version: version,
    os: 'linux',
    arch: 'arm64',
    runner: runner,
    fetch: fetch ?? fetcherOf(next),
    log: said.add,
    bundle: bundle ?? running.path,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_updater_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = RunnerPaths(p.join(directory.path, 'runner'));
    said = [];
    running = writeBundle(directory, version: '1.0.0');
    next = tarBundle(writeBundle(directory, version: '1.1.0'));
  });

  group('wantsUpdateTo', () {
    test('wants the version of the engine when it is not its own', () {
      final subject = updater();

      expect(subject.wantsUpdateTo('1.1.0'), isTrue);
      expect(subject.wantsUpdateTo('0.9.0'), isTrue);
      expect(subject.wantsUpdateTo('1.0.0'), isFalse);
      expect(said, isEmpty);
    });

    test('does not want a version that is no folder name', () {
      final subject = updater();

      expect(subject.wantsUpdateTo('../evil'), isFalse);
      expect(subject.wantsUpdateTo('../evil'), isFalse);

      expect(said, hasLength(1), reason: 'said once');
      expect(said.single, contains('not a version name'));
    });

    test('does not want a version that failed on this machine', () {
      updater().journal.rolledBack('1.1.0');
      final subject = updater();

      expect(subject.wantsUpdateTo('1.1.0'), isFalse);
      expect(subject.wantsUpdateTo('1.1.0'), isFalse);
      expect(subject.wantsUpdateTo('1.2.0'), isTrue);

      expect(said.single, contains('did not start on this machine'));
    });

    test('does not want a version it gave up on', () {
      final subject = updater()..giveUp('1.1.0');

      expect(subject.wantsUpdateTo('1.1.0'), isFalse);
      expect(said, isEmpty);
    });
  });

  group('update', () {
    test('downloads, unpacks, tries and switches to the new version', () async {
      final asked = <({String os, String arch})>[];
      final subject = updater(fetch: fetcherOf(next, asked: asked));

      final outcome = await subject.update('1.1.0');

      expect(outcome, isA<Updated>());
      expect((outcome as Updated).version, '1.1.0');
      expect(asked, [(os: 'linux', arch: 'arm64')]);
      expect(subject.versions.currentVersion(), '1.1.0');
      expect(subject.versions.has('1.1.0'), isTrue);
      expect(
        File(paths.currentExecutable).readAsStringSync(),
        contains('1.1.0'),
      );
      expect(
        Directory(paths.updates).existsSync(),
        isFalse,
        reason: 'cleaned up',
      );
      expect(said, contains('Updating from 1.0.0 to 1.1.0.'));
      expect(said, contains('Switched to version 1.1.0.'));
    });

    test(
      'keeps the running version for a rollback and records the update',
      () async {
        final subject = updater();

        await subject.update('1.1.0');

        expect(subject.versions.has('1.0.0'), isTrue, reason: 'adopted');
        expect(subject.journal.pending!.from, '1.0.0');
        expect(subject.journal.pending!.to, '1.1.0');
      },
    );

    test(
      'goes back to the version `current` pointed at, not the one that runs',
      () async {
        final first = updater();
        await first.update('1.1.0');
        // A second update, from the runner that was started as 1.1.0.
        final again = updater(
          version: '1.1.0',
          bundle: p.join(paths.versionDirectory('1.1.0')),
          fetch: fetcherOf(tarBundle(writeBundle(directory, version: '1.2.0'))),
        );

        await again.update('1.2.0');

        expect(again.journal.pending!.from, '1.1.0');
        expect(again.versions.currentVersion(), '1.2.0');
      },
    );

    test('does not copy a bundle that is not one', () async {
      final subject = updater(bundle: p.join(directory.path, 'x'));
      // `bundle` is null when xp does not run from a bundle.
      final unbundled = RunnerUpdater(
        paths: paths,
        version: '1.0.0',
        os: 'linux',
        arch: 'arm64',
        runner: const IoProcessRunner(),
        fetch: fetcherOf(next),
        log: said.add,
      );

      expect(await unbundled.update('1.1.0'), isA<Updated>());

      expect(unbundled.versions.has('1.0.0'), isFalse);
      expect(unbundled.versions.currentVersion(), '1.1.0');
      expect(subject.bundle, isNotNull);
    });

    test('replaces the folder of the version when it was installed', () async {
      final subject = updater();
      await subject.update('1.1.0');
      subject.versions.switchTo('1.0.0');

      expect(await updater().update('1.1.0'), isA<Updated>());
      expect(updater().versions.currentVersion(), '1.1.0');
    });

    group('refuses', () {
      Future<void> expectNothingSwitched(
        UpdateOutcome outcome,
        Pattern reason,
      ) async {
        expect(outcome, isA<UpdateFailed>());
        final failed = outcome as UpdateFailed;
        expect(failed.version, '1.1.0');
        expect(
          failed.message,
          allOf(
            contains('Cannot update to version 1.1.0'),
            contains(reason),
            contains('stays on 1.0.0'),
          ),
        );
        expect(said, contains(failed.message));
        expect(File(paths.currentLink).existsSync(), isFalse);
        expect(updater().versions.has('1.1.0'), isFalse);
        expect(updater().journal.pending, isNull);
        expect(Directory(paths.updates).existsSync(), isFalse);
      }

      test('a bundle whose digest is not the announced one', () async {
        final subject = updater(fetch: fetcherOf(next, sha256: 'a' * 64));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'not what the engine announced',
        );
      });

      test('a bundle whose size is not the announced one', () async {
        final subject = updater(
          fetch: fetcherOf(next, length: next.length + 1),
        );

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'not what the engine announced',
        );
      });

      test('an engine that announces neither digest nor size', () async {
        final subject = updater(fetch: fetcherOf(next, announce: false));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'did not say the SHA-256',
        );
      });

      test('an engine that has no bundle for the machine', () async {
        final subject = updater(
          fetch: ({required os, required arch}) async =>
              throw const ApiException(
                'This engine has no runner bundle for linux-arm64.',
                statusCode: 404,
              ),
        );

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'no runner bundle for linux-arm64',
        );
      });

      test('an engine that cannot be reached', () async {
        final subject = updater(
          fetch: ({required os, required arch}) async =>
              throw const ConnectionException('Connection refused.'),
        );

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'Connection refused',
        );
      });

      test('a file that is no archive', () async {
        final subject = updater(fetch: fetcherOf([1, 2, 3, 4]));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'does not unpack',
        );
      });

      test('a bundle without bin/xp', () async {
        final bundle = writeBundle(
          directory,
          version: '1.1.0',
          withExecutable: false,
        );
        final subject = updater(fetch: fetcherOf(tarBundle(bundle)));

        await expectNothingSwitched(await subject.update('1.1.0'), 'no bin/xp');
      });

      test('a bin/xp that cannot be run', () async {
        final bundle = writeBundle(
          directory,
          version: '1.1.0',
          executable: false,
        );
        final subject = updater(fetch: fetcherOf(tarBundle(bundle)));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'not executable',
        );
      });

      test('a bundle that says another version', () async {
        final bundle = writeBundle(
          directory,
          version: '1.1.0',
          versionOutput: '1.0.5',
        );
        final subject = updater(fetch: fetcherOf(tarBundle(bundle)));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'is xp 1.0.5, not 1.1.0',
        );
      });

      test('a bundle that does not start', () async {
        final bundle = writeBundle(directory, version: '1.1.0', exitCode: 3);
        final subject = updater(fetch: fetcherOf(tarBundle(bundle)));

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'does not start (exit 3)',
        );
      });

      test('a version that is no folder name', () async {
        final subject = updater();

        final outcome = await subject.update('../evil');

        expect(outcome, isA<UpdateFailed>());
        expect(
          (outcome as UpdateFailed).message,
          contains('not a version name'),
        );
        expect(File(paths.currentLink).existsSync(), isFalse);
      });

      test('a machine without tar', () async {
        final subject = updater(
          runner: FakeProcessRunner((call) => const ProcessOutput(exitCode: 0))
            ..startError = const ProcessStartException('tar', 'not found'),
        );

        await expectNothingSwitched(await subject.update('1.1.0'), 'not found');
      });

      test('a program that hangs', () async {
        final subject = updater(
          runner: FakeProcessRunner(
            (call) => throw TimeoutException('tar did not finish'),
          ),
        );

        await expectNothingSwitched(
          await subject.update('1.1.0'),
          'did not finish in time',
        );
      });

      test('a current that is a real folder, and forgets the update', () async {
        Directory(paths.currentLink).createSync(recursive: true);
        final subject = updater();

        final outcome = await subject.update('1.1.0');

        expect(outcome, isA<UpdateFailed>());
        expect(subject.journal.pending, isNull);
        expect(Directory(paths.currentLink).existsSync(), isTrue);
      });

      test('and does not ask again for the version that failed', () async {
        final subject = updater(fetch: fetcherOf([1, 2]));
        await subject.update('1.1.0');

        expect(subject.wantsUpdateTo('1.1.0'), isFalse);
        expect(subject.wantsUpdateTo('1.2.0'), isTrue);
      });
    });
  });

  group('rolling back', () {
    test('lets a new version start while it has tries left', () async {
      await updater().update('1.1.0');
      final started = updater(version: '1.1.0');

      for (var i = 0; i < maxUnconfirmedStarts; i++) {
        expect(started.checkStart(), isNull);
      }

      expect(started.versions.currentVersion(), '1.1.0');
    });

    test(
      'goes back after too many starts that never reached the engine',
      () async {
        await updater().update('1.1.0');
        final started = updater(version: '1.1.0');
        for (var i = 0; i < maxUnconfirmedStarts; i++) {
          started.checkStart();
        }

        expect(started.checkStart(), '1.0.0');

        expect(started.versions.currentVersion(), '1.0.0');
        expect(started.journal.pending, isNull);
        expect(started.journal.blocked, '1.1.0');
        expect(
          said.last,
          allOf(
            contains('going back to 1.0.0'),
            contains('does not update to 1.1.0 again'),
          ),
        );
        // The runner that is back does not want 1.1.0.
        expect(updater().wantsUpdateTo('1.1.0'), isFalse);
      },
    );

    test('stays when the version before is gone', () async {
      await updater().update('1.1.0');
      final started = updater(version: '1.1.0');
      Directory(paths.versionDirectory('1.0.0')).deleteSync(recursive: true);
      for (var i = 0; i < maxUnconfirmedStarts; i++) {
        started.checkStart();
      }

      expect(started.checkStart(), isNull);

      expect(started.versions.currentVersion(), '1.1.0');
      expect(started.journal.pending, isNull);
      expect(said.last, contains('not installed any more'));
    });

    test('a start of a runner that was not updated is nothing', () {
      expect(updater().checkStart(), isNull);
    });
  });

  group('connected', () {
    test('proves the update and keeps only the two versions', () async {
      await updater().update('1.1.0');
      final other = Directory(paths.versionDirectory('0.5.0'))
        ..createSync(recursive: true);
      final started = updater(version: '1.1.0')
        ..checkStart()
        ..connected('1.1.0');

      expect(started.journal.pending, isNull);
      expect(started.versions.has('1.0.0'), isTrue);
      expect(started.versions.has('1.1.0'), isTrue);
      expect(other.existsSync(), isFalse);
      expect(said.last, 'Updated from 1.0.0 to 1.1.0.');
    });

    test('is nothing for a runner that was not updated', () {
      updater().connected('1.0.0');

      expect(said, isEmpty);
    });
  });
}
