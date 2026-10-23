// Drives a real `xpd` through a dev build of the fixture app, against fake
// servers: tool/e2e/release_e2e.sh runs it.
//
// What it starts, all on loopback ports and in the work folder:
//
//   - a fake Firebase App Distribution (`xp_fake_firebase`), which takes the
//     version of an upload from its file name because it cannot read the
//     manifest of a real APK,
//   - a minimal fake GitHub REST API that knows one repository, whose clone
//     URL is a bare repository made from the fixture,
//   - `xpd serve` (the AOT bundle the script built) with XPD_TEST_* pointing
//     at the two fakes and its secrets in a file, never in the Keychain.
//
// It then talks to the engine over HTTP only, as a client would: adds the
// fixture as a project, saves a Firebase service account, dispatches
// `dev-build` for Android and waits for it. It checks that the APK, the
// manifest and a Firebase release exist, that the bytes the fake received are
// the stored APK, and that a second production release of the project waits
// for the first (the project lock) and takes its turn once the first is gone.
//
// `--mode prod` walks a production release through the whole release flow
// (Phase 12b) against fake App Store Connect, Google Play, Firebase and GitHub:
// see `_prod` for what it does and checks, and tool/e2e/release_e2e.sh for what
// is real and what is faked.
//
// `--mode mcp` (Phase 13, tool/e2e/mcp_gate_e2e.sh) drives the same engine
// through `xp`: `xp connect` saves a CLI token and an MCP token, `xp mcp` runs
// as a stdio subprocess that this script speaks MCP JSON-RPC to, and an
// MCP-dispatched production release must stop at a pending approval that the
// MCP token cannot decide: see `_mcpGate`.
//
// `--mode runner-loss` (Phase 14b, tool/e2e/runner_loss_e2e.sh) pairs and
// starts a real `xp runner` as a process of its own, gives it jobs that hold
// per-job secrets, kills it with SIGKILL in the middle of them and checks the
// loss rule of the engine after the lease lapses and that the restarted runner
// leaves no secret file, temporary keychain or process behind: see
// `_runnerLoss`.
//
// `--mode runner-build` (Phase 14b, tool/e2e/runner_build_e2e.sh) builds the
// fixture app with the built-in `dev-build` workflow on a real `xp runner`: the
// engine cannot build Android (its environment has no Android SDK), the runner
// can, so the build job of the workflow is leased to the runner, which fetches
// the commit, bumps the version, builds the APK and uploads it; the check and
// the upload to Firebase run on the engine: see `_runnerBuild`.
//
// `--mode runner-offline` (runner onboarding R5, tool/e2e/runner_offline_e2e.sh)
// runs the engine with a lease of a few seconds, gives a real `xp runner` a
// job, then stops the engine (SIGSTOP, then SIGKILL) for longer than a lease:
// the runner fences the job it can no longer hold, and when the engine comes
// back on the same address the runner reconnects by itself and the job
// follows the loss rule: see `_runnerOffline`.
//
// Usage: dart run tool/release_e2e.dart --mode dev|prod|mcp|runner-loss|runner-build|runner-offline
//          --xpd <executable> --fixture <dir> --work <dir>
//          [--flutter-sdk <dir>] [--xp <executable>]
//
// Exits 0 only if everything held; progress goes to standard error.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xp_fake_play/xp_fake_play.dart';
import 'package:xpd/xpd.dart';

const _firebaseAppId = '1:684690133351:android:b434734f585770367c1fc2';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'mode',
      allowed: [
        'dev',
        'prod',
        'mcp',
        'runner-loss',
        'runner-build',
        'runner-offline',
      ],
      defaultsTo: 'dev',
    )
    ..addOption('xpd', mandatory: true, help: 'The xpd executable.')
    ..addOption('xp', help: 'The xp executable (mcp and the runner modes).')
    ..addOption('fixture', mandatory: true, help: 'The fixture app folder.')
    ..addOption('work', mandatory: true, help: 'An empty scratch folder.')
    ..addOption(
      'flutter-sdk',
      help:
          'A Flutter SDK that already is the version the fixture pins. It is '
          "linked into the engine's cache, so nothing is downloaded.",
    );
  final options = parser.parse(arguments);
  final e2e = _E2e(
    mode: options['mode'] as String,
    xpd: options['xpd'] as String,
    xp: options['xp'] as String?,
    fixture: options['fixture'] as String,
    work: options['work'] as String,
    flutterSdk: options['flutter-sdk'] as String?,
  );
  try {
    await e2e.run();
    _log('all checks passed');
    exitCode = 0;
  } on _Failure catch (failure) {
    stderr.writeln('release_e2e: ${failure.message}');
    await e2e.explain();
    exitCode = 1;
  } finally {
    await e2e.stop();
  }
}

class _Failure implements Exception {
  const new(this.message);

  final String message;
}

class _E2e {
  new({
    required this.mode,
    required this.xpd,
    required this.xp,
    required this.fixture,
    required this.work,
    required this.flutterSdk,
  }) : data = p.join(work, 'data');

  final String mode;
  final String xpd;
  final String? xp;
  final String fixture;
  final String work;
  final String? flutterSdk;
  final String data;

  FakeFirebaseServer? _firebase;
  _FakeGitHub? _github;
  FakeAscServer? _asc;
  FakePlayServer? _play;
  Process? _engine;
  Process? _runnerProcess;
  final _runnerLog = StringBuffer();
  late Uri _url;
  late String _token;
  final _engineLog = StringBuffer();
  final _client = HttpClient();
  String? _lastJob;
  String? _lastRun;
  late _SourceSnapshot _sourceBefore;
  final _events = <SequencedEvent>[];
  WebSocket? _eventSocket;

  /// The secrets of the fakes: nothing of these may reach a log, the
  /// database or the arguments of a process.
  static const _githubToken = 'ghp_e2e_made_up_token';

  String get _argvLog => p.join(work, 'argv.log');

  // ------------------------------------------------------------------- run

  Future<void> run() async {
    Directory(work).createSync(recursive: true);
    final origin = _makeRepositories();
    _sourceBefore = _SourceSnapshot.of(p.join(work, 'clone'));
    _firebase =
        await FakeFirebaseServer.start(
            pollsBeforeDone: 0,
            readVersionFromFileName: true,
          )
          ..addApp('684690133351', _firebaseAppId, groups: {'testers'});
    _github = await _FakeGitHub.start(origin, token: _githubToken);
    if (mode == 'prod') {
      _asc = await FakeAscServer.start();
      _play = await FakePlayServer.start()
        ..sendsToReview = true;
      _writeShims();
      _wrapFlutter();
    } else {
      _linkFlutter();
    }
    await _startEngine();

    final clone = p.join(work, 'clone');
    final project = await _post('/projects', {'path': clone}, expect: 201);
    final projectId = project['id']! as String;
    final flavors = [
      for (final app in (project['profile'] as Map)['apps'] as List)
        for (final flavor in (app as Map)['flavors'] as List)
          (flavor as Map)['name'],
    ];
    _expect(
      flavors.toSet().containsAll(['dev', 'prod']),
      'the scan found the flavors dev and prod, not $flavors',
    );
    _log('added project $projectId with the flavors $flavors');
    if (mode == 'mcp') {
      await _mcpGate(projectId);
      return;
    }
    if (mode == 'runner-loss') {
      await _runnerLoss(projectId);
      return;
    }
    if (mode == 'runner-build') {
      await _runnerBuild(projectId);
      return;
    }
    if (mode == 'runner-offline') {
      await _runnerOffline(projectId);
      return;
    }
    if (mode == 'prod') {
      await _prod(project);
      return;
    }

    await _addCredential(
      projectId,
      flavor: 'dev',
      name: 'Firebase · e2e',
      fields: {
        'kind': 'firebase_sa',
        'serviceAccount': _firebase!.serviceAccountJson(),
      },
    );
    _log('added the Firebase service account and assigned it to dev');

    final workflows = await _get('/projects/$projectId/workflows');
    final byName = {
      for (final workflow in workflows['workflows'] as List)
        (workflow as Map)['name']! as String: workflow['id']! as String,
    };
    _expect(
      byName.keys.toSet().containsAll([
        'dev-build',
        'prod-release',
        'shorebird-patch',
        'test',
      ]),
      'the built-in workflows are there, not ${byName.keys}',
    );

    await _devBuild(projectId, byName['dev-build']!);
    await _lock(projectId, byName['prod-release']!);
  }

  // ------------------------------------------------------------- dev build

  Future<void> _devBuild(String projectId, String workflowId) async {
    final run = await _post(
      '/projects/$projectId/workflows/$workflowId/dispatch',
      {
        'platforms': ['android'],
        'flavors': ['dev'],
        'inputs': {
          'firebaseAppIds': {
            'dev': {'android': _firebaseAppId},
          },
          'testerGroups': ['testers'],
          'notes': 'built by release_e2e',
        },
      },
      expect: 202,
    );
    final jobs = run['jobs'] as List;
    final ids = {
      for (final job in jobs)
        (job as Map)['name']! as String: job['id']! as String,
    };
    _expect(
      ids.keys.toList().toString() ==
          [
            'Check dev for android',
            'Build dev for android',
            'Upload dev for android',
          ].toString(),
      'dev-build for android is a check, a build and an upload job (ADR '
      '0010): ${ids.keys}',
    );
    final jobId = ids['Build dev for android']!;
    final uploadId = ids['Upload dev for android']!;
    _lastJob = uploadId;
    _log('dispatched run ${run['id']} (build ${run['build']}), jobs $ids');

    final upload = await _waitForJob(uploadId, const Duration(minutes: 25), {
      'succeeded',
      'failed',
      'cancelled',
      'waiting_for_approval',
    });
    if (upload['state'] != 'succeeded') {
      throw _Failure('the upload ${upload['state']}: ${upload['message']}');
    }
    final job = await _get('/jobs/$jobId');
    final kinds = [
      for (final step in job['steps'] as List) (step as Map)['kind'],
    ];
    _log('steps of the build job: $kinds');
    _expect(
      RemoteStepPolicy.engineOnlyIn(kinds.cast<String>()).isEmpty,
      'the build job has no step only the engine runs: $kinds',
    );
    _expect(
      (upload['steps'] as List).length == 1 &&
          ((upload['steps'] as List).single as Map)['kind'] ==
              'upload.firebase',
      'the upload job uploads to Firebase: ${upload['steps']}',
    );

    final artifacts =
        (await _get('/jobs/$jobId/artifacts'))['artifacts'] as List;
    Map<dynamic, dynamic> artifact(String kind) => artifacts.firstWhere(
      (a) => (a as Map)['kind'] == kind,
      orElse: () => throw _Failure('the job stored no $kind: $artifacts'),
    ) as Map;
    final apk = artifact('apk');
    final manifest = artifact('manifest');
    final build = run['build']! as int;
    _expect(
      apk['name'] == 'dev-1.0.0+$build.apk',
      'the APK is named for the version and build: ${apk['name']}',
    );

    final apkBytes = await _download('/artifacts/${apk['id']}/download');
    _expect(
      sha256OfBytes(apkBytes) == apk['sha256'] &&
          apkBytes.length == apk['size'],
      'the downloaded APK has the size and SHA-256 the engine recorded',
    );
    _expect(
      apkBytes.length > 4 && apkBytes[0] == 0x50 && apkBytes[1] == 0x4b,
      'the APK is a zip',
    );
    final manifestText = utf8.decode(
      await _download('/artifacts/${manifest['id']}/download'),
    );
    for (final expected in [
      '"version": "1.0.0"',
      '"build": $build',
      '"dev"',
      '"sha256": "${apk['sha256']}"',
    ]) {
      _expect(
        manifestText.contains(expected),
        'manifest.json contains $expected',
      );
    }

    final releases = _firebase!.apps[_firebaseAppId]!.releases;
    _expect(releases.length == 1, 'Firebase has one release, not $releases');
    final release = releases.single;
    _expect(
      release.displayVersion == '1.0.0' && release.buildVersion == '$build',
      'the Firebase release is 1.0.0+$build, not '
      '${release.displayVersion}+${release.buildVersion}',
    );
    _expect(
      sha256OfBytes(release.binary) == apk['sha256'],
      'the bytes Firebase received are the stored APK',
    );
    _log(
      'the dev build is stored (${apk['name']}, ${apk['sha256']}), has a '
      'manifest and is in Firebase as ${release.displayVersion}+'
      '${release.buildVersion}',
    );
  }

  // --------------------------------------------------------- project lock

  Future<void> _lock(String projectId, String workflowId) async {
    Future<Map<String, dynamic>> dispatch() =>
        _post('/projects/$projectId/workflows/$workflowId/dispatch', {
          'platforms': ['android'],
          'flavors': ['prod'],
        }, expect: 202);
    final first = await dispatch();
    final second = await dispatch();
    final firstPrepare = _jobOf(first, 0);
    final secondPrepare = _jobOf(second, 0);
    _lastJob = firstPrepare;

    // Nothing in this script approves the gate, so the first release stops
    // at it and keeps the project.
    final stopped = await _waitForJob(
      firstPrepare,
      const Duration(minutes: 5),
      {'waiting_for_approval', 'failed'},
    );
    _expect(
      stopped['state'] == 'waiting_for_approval',
      'the first release stops at its gate, not ${stopped['state']}: '
      '${stopped['message']}',
    );
    var waiting = await _get('/jobs/$secondPrepare');
    _expect(
      waiting['state'] == 'queued',
      'the second release queues while the first holds the project, not '
      '${waiting['state']}',
    );
    _expect(
      '${waiting['message']}'.contains(first['id'] as String),
      'the second release says which run it waits for: ${waiting['message']}',
    );
    _log('the second production release queues behind ${first['id']}');

    await _post('/runs/${first['id']}/cancel', null);
    _lastJob = secondPrepare;
    waiting = await _waitForJob(secondPrepare, const Duration(minutes: 5), {
      'waiting_for_approval',
      'failed',
    });
    _expect(
      waiting['state'] == 'waiting_for_approval',
      'the second release takes its turn once the first is gone, not '
      '${waiting['state']}: ${waiting['message']}',
    );
    await _post('/runs/${second['id']}/cancel', null);
    _log('the second production release ran once the first ended');
  }

  // ----------------------------------------------------------- runner loss

  /// Phase 14b: killing a runner in the middle of a job.
  ///
  /// What is real: the engine (`xpd serve --slots 1`, so that one long job on
  /// the engine keeps its only slot and the next jobs go to the runner), the
  /// `xp` bundle as the runner in a process of its own with its own data
  /// folder (paired with `xp runner pair`; its credential in the encrypted
  /// file, never a Keychain), the source (the runner fetches the exact commit
  /// from the bare repository that plays GitHub with `git fetch`, in a bare
  /// cache of its own, and checks it out in a worktree of its own: ADR 0009),
  /// the step runner and its process groups, the per-job secret folder and
  /// the loss rule of the engine. What is faked: the keystore (some bytes,
  /// and a `keytool` shim that accepts it on save).
  ///
  /// Two jobs go to the runner, each with a `command` step that holds a
  /// keystore secret (a file and a password) and sleeps: one declares a side
  /// effect, one does not. The script
  ///
  ///   1. waits until both run on the runner with their secret files in the
  ///      runner's secret folder, and checks that the engine's stored log has
  ///      the password masked,
  ///   2. kills the runner with SIGKILL (no clean-up of its own can run),
  ///   3. checks that nothing changes at once: the jobs still hold their
  ///      leases, and the crash left the secret files and the sleeping
  ///      processes behind,
  ///   4. waits for the lease to lapse (90 s plus the sweep, the production
  ///      timing) and checks the loss rule (D-08): the job with the side
  ///      effect is `waiting_for_resume` (never repeated by itself, and that
  ///      is how a job with a step that cannot be repeated "fails" when its
  ///      runner is lost), the one without is queued again; both with a
  ///      `runner.lease_lost` event, and neither runs again by itself,
  ///   5. starts the runner again and checks that it cleaned up after the
  ///      dead one: no secret file, no temporary keychain, no process left,
  ///   6. resumes the job with the side effect, which the runner takes, and
  ///      cancels it: the process group ends and the secret files are gone.
  Future<void> _runnerLoss(String projectId) async {
    final xp = this.xp;
    if (xp == null) {
      throw const _Failure('--xp is required for --mode runner-loss');
    }
    await _listenToEvents();
    final runnerData = p.join(work, 'runner-data');
    final environment = _runnerEnvironment();
    final identity = await _pairRunner(xp, runnerData, environment);
    Future<void> startRunner() => _startRunner(xp, runnerData, environment);

    await startRunner();
    _log('the runner is online');

    // --- the jobs
    final keystoreId = await _addCredential(
      projectId,
      flavor: 'dev',
      name: 'Upload keystore · e2e',
      fields: {
        'kind': 'keystore',
        'keystore': base64Encode(utf8.encode(_fakeKeystore)),
        'storePassword': _fakeStorePassword,
        'keyAlias': 'upload',
      },
    );
    final secretKey = 'credential.$keystoreId';

    Future<String> workflow(String name, String jobs) async {
      final created = await _post('/projects/$projectId/workflows', {
        'name': name,
        'yaml':
            'schema: 1\nname: $name\nstages:\n  - name: only\n    jobs:\n'
            '$jobs',
      }, expect: 201);
      return created['id']! as String;
    }

    String job(String id, String sleep, {required bool sideEffect}) =>
        '''
      $id:
        name: $id
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: sh
              arguments:
                - -c
                - 'echo "keystore=\$E2E_KEYSTORE"; echo "password=\$E2E_STORE_PASSWORD"; test -s "\$E2E_KEYSTORE" && echo secret-file-ok; sleep $sleep'
              secretFiles:
                E2E_KEYSTORE: $secretKey
              secretEnvironment:
                E2E_STORE_PASSWORD: $secretKey.storePassword
              sideEffect: $sideEffect
''';
    final occupy = await workflow('occupy', '''
      occupy:
        name: occupy
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: sleep
              arguments: ['3600']
''');
    final holdEffect = await workflow(
      'hold-effect',
      job('effect', '3571', sideEffect: true),
    );
    final holdPure = await workflow(
      'hold-pure',
      job('pure', '3572', sideEffect: false),
    );
    Future<Map<String, dynamic>> dispatch(String workflowId) =>
        _post('/projects/$projectId/workflows/$workflowId/dispatch', {
          'platforms': ['android'],
          'flavors': ['dev'],
        }, expect: 202);

    // The only slot of the engine is taken, so the jobs below go to the runner.
    final occupier = _jobOf(await dispatch(occupy), 0);
    await _waitForJob(occupier, const Duration(minutes: 2), {'running'});
    final effectRun = await dispatch(holdEffect);
    final pureRun = await dispatch(holdPure);
    _lastRun = effectRun['id'] as String?;
    final effect = _jobOf(effectRun, 0);
    final pure = _jobOf(pureRun, 0);
    _lastJob = effect;
    for (final id in [effect, pure]) {
      final running = await _waitForJob(id, const Duration(minutes: 3), {
        'running',
        'failed',
      });
      _expect(
        running['state'] == 'running' && running['runnerId'] != null,
        'job $id runs on the runner, not ${running['state']}: '
        '${running['message']}',
      );
    }
    final runnerId = identity['runnerId'];
    _expect(
      (await _get('/jobs/$effect'))['runnerId'] == runnerId,
      'the job runs on the paired runner',
    );
    _log('both jobs run on the runner');

    // --- secrets reach the runner's secret folder, and only masked into logs
    final held = await _waitFor(
      'the secret files of both jobs in the secret folder of the runner',
      () {
        final files = _secretFiles(runnerData);
        final keystores = files.where(
          (f) => p.basename(f.path).endsWith('E2E_KEYSTORE'),
        );
        return keystores.length >= 2 ? files : null;
      },
    );
    for (final file in held.where(
      (f) => p.basename(f.path).endsWith('E2E_KEYSTORE'),
    )) {
      _expect(
        file.readAsStringSync() == _fakeKeystore,
        'the keystore file has the bytes the engine delivered',
      );
    }
    _expect(
      held.any((f) => p.basename(f.path).startsWith('delivered-')),
      'the delivered secrets are kept in the secret folder too',
    );
    _expect(_alive('sleep 3571') && _alive('sleep 3572'), 'the jobs sleep');
    await _waitFor('the log of the job to have the masked password', () {
      final logs = _storedLogs(effect);
      return logs.contains('password=***') && logs.contains('secret-file-ok')
          ? logs
          : null;
    });
    _expect(
      !_storedLogs(effect).contains(_fakeStorePassword) &&
          !_runnerLog.toString().contains(_fakeStorePassword),
      'the password is in no stored log and not in the output of the runner',
    );

    // --- the crash
    final killedAt = DateTime.now();
    _runnerProcess!.kill(ProcessSignal.sigkill);
    await _runnerProcess!.exitCode;
    _log('killed the runner with SIGKILL');
    _expect(
      _secretFiles(runnerData).isNotEmpty && _alive('sleep 3571'),
      'a runner killed with SIGKILL could not clean up: its secret files and '
      'its processes are still there',
    );
    await Future<void>.delayed(const Duration(seconds: 15));
    for (final id in [effect, pure]) {
      _expect(
        (await _get('/jobs/$id'))['state'] == 'running',
        'job $id still holds its lease 15 s after the crash (the lease lasts '
        '90 s)',
      );
    }

    // --- the lease lapses
    final lost = await _waitForJob(effect, const Duration(minutes: 4), {
      'waiting_for_resume',
      'failed',
      'cancelled',
      'queued',
    });
    final elapsed = DateTime.now().difference(killedAt);
    _expect(
      elapsed >= const Duration(seconds: 60),
      'the job was not taken from the runner before its lease lapsed '
      '(after ${elapsed.inSeconds} s)',
    );
    _expect(
      lost['state'] == 'waiting_for_resume' &&
          lost['runnerId'] == null &&
          '${lost['message']}'.contains('lost its lease') &&
          '${lost['message']}'.contains('never repeated'),
      'the job with a side effect waits for a resume and says why: '
      '${lost['state']} ${lost['message']}',
    );
    final steps = lost['steps'] as List;
    _expect(
      (steps.last as Map)['state'] == 'interrupted',
      'its running step is interrupted: ${steps.last}',
    );
    final requeued = await _waitForJob(pure, const Duration(seconds: 30), {
      'queued',
      'failed',
      'cancelled',
    });
    _expect(
      requeued['state'] == 'queued' && requeued['runnerId'] == null,
      'the job without a side effect is queued again: ${requeued['state']}',
    );
    await Future<void>.delayed(const Duration(seconds: 12));
    _expect(
      (await _get('/jobs/$effect'))['state'] == 'waiting_for_resume' &&
          (await _get('/jobs/$pure'))['state'] == 'queued',
      'neither job runs again by itself',
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final lapses = _events
        .map((e) => e.event)
        .whereType<RunnerLeaseLost>()
        .toList();
    _expect(
      lapses.length == 2 &&
          lapses.every((e) => e.reason == 'lapsed' && e.runnerId == runnerId) &&
          lapses.map((e) => e.jobId).toSet().containsAll([effect, pure]),
      'a runner.lease_lost event (lapsed) for each job: $lapses',
    );
    _log(
      'after ${elapsed.inSeconds} s the engine took the jobs back: '
      'waiting_for_resume (side effect) and queued',
    );

    // --- the restart cleans up after the dead runner
    await _post('/jobs/$pure/cancel', null);
    _runnerLog.clear();
    await startRunner();
    await _waitFor('the start-up clean-up to be reported', () {
      final text = _runnerLog.toString();
      return text.contains('Cleaned up after an earlier run') ? text : null;
    });
    _expect(
      _secretFiles(runnerData).isEmpty,
      'no secret file is left after the runner restarted: '
      '${_secretFiles(runnerData).map((f) => f.path).toList()}',
    );
    _expect(
      !_alive('sleep 3571') && !_alive('sleep 3572'),
      'the processes the dead runner left are stopped',
    );
    final keychains = Directory(p.join(runnerData, 'keychains'));
    _expect(
      !keychains.existsSync() || keychains.listSync().isEmpty,
      'no temporary keychain is left',
    );
    if (Platform.isMacOS) {
      final listed = Process.runSync('/usr/bin/security', [
        'list-keychains',
        '-d',
        'user',
      ]);
      _expect(
        !'${listed.stdout}'.contains(runnerData),
        'the keychain search list of the user does not name the runner',
      );
    }
    _log('the restarted runner left no secret, keychain or process behind');

    // --- the job can be resumed; cancelling it wipes its secrets again
    await _post('/jobs/$effect/resume', null, expect: 202);
    final again = await _waitForJob(effect, const Duration(minutes: 2), {
      'running',
      'failed',
    });
    _expect(
      again['state'] == 'running' && again['runnerId'] == runnerId,
      'the resumed job runs on the restarted runner: ${again['state']} '
      '${again['message']}',
    );
    await _waitFor('the secret file of the resumed job', () {
      final files = _secretFiles(runnerData);
      return files.isEmpty ? null : files;
    });
    await _post('/jobs/$effect/cancel', null);
    await _waitFor('the secrets to be wiped when the job is cancelled', () {
      return _secretFiles(runnerData).isEmpty && !_alive('sleep 3571')
          ? true
          : null;
    });
    _log('cancelling the job stopped its process group and wiped its secrets');
    await _post('/jobs/$occupier/cancel', null);
  }

  // ------------------------------------------------------------ the runner

  /// The environment of `xp runner`: nothing of `XP_*` from this machine, the
  /// credential in a file in its data folder (never a Keychain), and the URL
  /// of the repository replaced, as there is no SSH key to read from.
  Map<String, String> _runnerEnvironment({String? path}) => {
    for (final entry in Platform.environment.entries)
      if (!entry.key.startsWith('XP_')) entry.key: entry.value,
    'XP_TEST_FILE_SECRETS': '1',
    'XP_NO_UPDATE_CHECK': '1',
    // The offer names the repository the engine knows (here a local path
    // that plays GitHub). A test points the runner at it all the same.
    'XP_RUNNER_TEST_SOURCE_URL': p.join(work, 'origin.git'),
    'PATH': ?path,
  };

  /// Runner onboarding R5: a runner outlives an engine that is away for
  /// longer than a lease.
  ///
  ///   1. pairs and starts a real `xp runner` and gives it a job with a side
  ///      effect (the engine's only slot is taken),
  ///   2. stops the engine with SIGSTOP for longer than the lease of 6 s plus
  ///      the runner's 15 s of grace: the runner fences the job (stops its
  ///      process and says so) although it never heard from the engine,
  ///   3. kills the engine with SIGKILL and starts it again on the same
  ///      address and data directory,
  ///   4. checks that the same runner process reconnects by itself within
  ///      60 s, and that the job follows the loss rule: a step with a side
  ///      effect makes it wait for a resume, never repeated by itself.
  Future<void> _runnerOffline(String projectId) async {
    final xp = this.xp;
    if (xp == null) {
      throw const _Failure('--xp is required for --mode runner-offline');
    }
    final runnerData = p.join(work, 'runner-data');
    final environment = _runnerEnvironment();
    await _pairRunner(xp, runnerData, environment);
    await _startRunner(xp, runnerData, environment);
    final runner = _runnerProcess!;
    var runnerExited = false;
    unawaited(runner.exitCode.then((_) => runnerExited = true));
    _log('the runner is online');

    Future<String> workflow(String name, String steps) async {
      final created = await _post('/projects/$projectId/workflows', {
        'name': name,
        'yaml':
            'schema: 1\nname: $name\nstages:\n  - name: only\n    jobs:\n'
            '      $name:\n        name: $name\n        steps:\n$steps',
      }, expect: 201);
      return created['id']! as String;
    }

    String sleep(String seconds, {required bool sideEffect}) =>
        '''
          - kind: git.checkout
          - kind: command
            with:
              executable: sleep
              arguments: ['$seconds']
              sideEffect: $sideEffect
''';
    Future<String> dispatch(String workflowId) async => _jobOf(
      await _post('/projects/$projectId/workflows/$workflowId/dispatch', {
        'platforms': ['android'],
        'flavors': ['dev'],
      }, expect: 202),
      0,
    );
    final occupier = await dispatch(
      await workflow('occupy', sleep('3600', sideEffect: false)),
    );
    await _waitForJob(occupier, const Duration(minutes: 2), {'running'});
    final held = await dispatch(
      await workflow('hold', sleep('3573', sideEffect: true)),
    );
    _lastJob = held;
    final running = await _waitForJob(held, const Duration(minutes: 3), {
      'running',
      'failed',
    });
    _expect(
      running['state'] == 'running' && running['runnerId'] != null,
      'the job runs on the runner, not ${running['state']}: '
      '${running['message']}',
    );
    await _waitFor('the job to sleep on the runner', () {
      return _alive('sleep 3573') ? true : null;
    });
    _log('the job runs on the runner');

    // --- the engine goes quiet: no answer, the socket stays open
    final engine = _engine!;
    final port = _url.port;
    engine.kill(ProcessSignal.sigstop);
    final stoppedAt = DateTime.now();
    _log('stopped the engine with SIGSTOP');
    await _waitFor('the runner to fence the job it can no longer hold', () {
      return _runnerLog.toString().contains(
            'Lost the lease of job $held while the engine was unreachable',
          )
          ? true
          : null;
    });
    final fencedAfter = DateTime.now().difference(stoppedAt);
    // The lease of 6 s plus 15 s of grace, counted from the last renewal
    // (a heartbeat every 2 s), so no sooner than about 19 s after the stop.
    _expect(
      fencedAfter >= const Duration(seconds: 15),
      'the runner kept the job for its lease and the grace '
      '(fenced after ${fencedAfter.inSeconds} s)',
    );
    await _waitFor('the process of the fenced job to end', () {
      return _alive('sleep 3573') ? null : true;
    });
    _log('the runner fenced the job after ${fencedAfter.inSeconds} s');

    // --- the engine dies and comes back on the same address
    engine.kill(ProcessSignal.sigkill);
    await engine.exitCode;
    await Future<void>.delayed(const Duration(seconds: 2));
    await _launchEngine(port: port);
    final backAt = DateTime.now();
    _expect(_url.port == port, 'the engine is back on port $port');
    await _waitFor('the runner to reconnect by itself', () {
      return _runnerLog.toString().contains('Connected again after')
          ? true
          : null;
    });
    final reconnected = await _waitForRunnerOnline(const Duration(seconds: 60));
    _expect(
      reconnected && !runnerExited,
      'the same runner process came back online within 60 s of the engine '
      '(after ${DateTime.now().difference(backAt).inSeconds} s)',
    );
    _log('the runner reconnected without a restart');

    // --- the loss rule
    final lost = await _waitForJob(held, const Duration(minutes: 1), {
      'waiting_for_resume',
      'queued',
      'failed',
      'cancelled',
    });
    // The engine that comes back finds the job running on a runner it holds
    // no lease for (JobRecovery): a step with a side effect makes it wait.
    _expect(
      lost['state'] == 'waiting_for_resume' &&
          lost['runnerId'] == null &&
          '${lost['message']}'.isNotEmpty,
      'the job with a side effect waits for a resume and says why: '
      '${lost['state']} ${lost['message']}',
    );
    await Future<void>.delayed(const Duration(seconds: 10));
    _expect(
      (await _get('/jobs/$held'))['state'] == 'waiting_for_resume' &&
          !_alive('sleep 3573'),
      'the job was not run again by itself',
    );
    _log('the job waits for a resume, as the loss rule says');
  }

  /// Whether a runner is online within [timeout].
  Future<bool> _waitForRunnerOnline(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final runners = (await _get('/runners'))['runners'] as List;
      if (runners.any((r) => (r as Map)['status'] == 'online')) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// Makes a pairing token, exchanges it with `xp runner pair` for the
  /// credential of a runner called `e2e-runner`, and checks that what the
  /// runner keeps in its data folder names no secret. Returns `runner.json`.
  Future<Map<String, dynamic>> _pairRunner(
    String xp,
    String runnerData,
    Map<String, String> environment,
  ) async {
    final pairing = await _post('/runners/pairing-tokens', {
      'name': 'e2e-runner',
    }, expect: 201);
    final paired = await Process.run(
      xp,
      [
        'runner',
        'pair',
        '--engine',
        _url.toString(),
        '--token',
        pairing['token']! as String,
        '--data-dir',
        runnerData,
      ],
      environment: environment,
      includeParentEnvironment: false,
    );
    _expect(
      paired.exitCode == 0,
      'xp runner pair exits 0, not ${paired.exitCode}: ${paired.stderr}',
    );
    final identity = jsonDecode(
      File(p.join(runnerData, 'runner.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    _expect(
      identity.keys.toSet().containsAll(['engine', 'runnerId', 'name']) &&
          identity.length == 3,
      'runner.json holds who the runner is and no credential: $identity',
    );
    _log('paired the runner ${identity['runnerId']}');
    return identity;
  }

  /// Starts `xp runner start` as a process of its own and waits until the
  /// engine lists the runner as online, with [capability] if one is given.
  Future<void> _startRunner(
    String xp,
    String runnerData,
    Map<String, String> environment, {
    String? capability,
  }) async {
    final process = _runnerProcess = await Process.start(
      xp,
      ['runner', 'start', '--data-dir', runnerData, '--slots', '2'],
      environment: environment,
      includeParentEnvironment: false,
    );
    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_runnerLog.writeln);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final runners = (await _get('/runners'))['runners'] as List;
      if (runners.any(
        (r) =>
            (r as Map)['status'] == 'online' &&
            (capability == null ||
                (r['capabilities'] as List).contains(capability)),
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw const _Failure('the runner did not come online in 90 s');
  }

  static const _fakeKeystore = 'FAKE-KEYSTORE-BYTES-FOR-E2E';
  static const _fakeStorePassword = 'fake-store-password-e2e-4471';

  /// Every file in the secret folders of the runner: its data folder, and the
  /// tmpfs folder of a Linux runner.
  List<File> _secretFiles(String runnerData) {
    final roots = <Directory>[Directory(p.join(runnerData, 'secrets'))];
    final shm = Directory('/dev/shm');
    if (shm.existsSync()) {
      roots.addAll(
        shm.listSync().whereType<Directory>().where(
          (d) => p.basename(d.path).startsWith('xpath-runner-'),
        ),
      );
    }
    return [
      for (final root in roots)
        if (root.existsSync())
          ...root.listSync(recursive: true).whereType<File>(),
    ];
  }

  /// Whether a process whose command line contains [pattern] is alive.
  bool _alive(String pattern) =>
      Process.runSync('pgrep', ['-f', pattern]).exitCode == 0;

  /// The stored log of the job [id] on the engine, all its steps.
  String _storedLogs(String id) {
    final directory = Directory(p.join(data, 'logs', id));
    if (!directory.existsSync()) return '';
    return [
      for (final file in directory.listSync().whereType<File>())
        file.readAsStringSync(),
    ].join('\n');
  }

  /// Calls [check] every second until it gives a value; fails after 3 minutes.
  Future<T> _waitFor<T>(String what, T? Function() check) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final value = check();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _Failure('timed out waiting for $what');
  }

  // ---------------------------------------------------------- runner build

  /// Phase 14b: the build job of `dev-build` on a runner (ADR 0010).
  ///
  /// The engine has no Android SDK, so the build job (which needs `android`)
  /// can only go to the runner; the check and the upload (an engine-only
  /// guard and `upload.firebase`) run on the engine. What it checks:
  ///
  ///   - the three jobs ran where they should: the build job on the runner,
  ///     the others on the engine,
  ///   - the runner fetched the commit into a bare cache of its own and built
  ///     in a worktree of its own (the paths of the engine's disk were
  ///     translated), and left no worktree, work folder or secret behind,
  ///   - the APK and the manifest the runner uploaded are in the engine's store
  ///     with the digests the runner computed, and Firebase received that
  ///     very APK from the upload job on the engine,
  ///   - the build number is the one allocated at dispatch.
  Future<void> _runnerBuild(String projectId) async {
    final xp = this.xp;
    if (xp == null) {
      throw const _Failure('--xp is required for --mode runner-build');
    }
    final runnerData = p.join(work, 'runner-data');
    // The runner's own Flutter cache has the pinned SDK, and no fvm answers.
    final pin =
        (jsonDecode(File(p.join(fixture, '.fvmrc')).readAsStringSync())
                as Map<String, dynamic>)['flutter']!
            as String;
    final sdk = flutterSdk;
    if (sdk != null) {
      final target = p.join(runnerData, 'toolchains', 'flutter', pin);
      Directory(p.dirname(target)).createSync(recursive: true);
      Link(target).createSync(sdk);
    }
    final shims = Directory(_fvmShim());
    final environment = _runnerEnvironment(
      path: '${shims.path}:${Platform.environment['PATH']}',
    );
    final identity = await _pairRunner(xp, runnerData, environment);
    await _startRunner(xp, runnerData, environment, capability: 'android');
    _log('the runner is online and can build Android; the engine cannot');

    // The deprecated per-flavor route on purpose: it still creates a named
    // credential and its assignment (ADR 0013).
    await _put('/projects/$projectId/credentials', {
      'app': '.',
      'flavor': 'dev',
      'kind': 'firebase_sa',
      'serviceAccount': _firebase!.serviceAccountJson(),
    });
    final workflows = await _get('/projects/$projectId/workflows');
    final devBuild =
        ((workflows['workflows'] as List).firstWhere(
              (w) => (w as Map)['name'] == 'dev-build',
            ) as Map)['id']!
            as String;
    final run = await _post(
      '/projects/$projectId/workflows/$devBuild/dispatch',
      {
        'platforms': ['android'],
        'flavors': ['dev'],
        'inputs': {
          'firebaseAppIds': {
            'dev': {'android': _firebaseAppId},
          },
          'testerGroups': ['testers'],
          'notes': 'built by a runner',
        },
      },
      expect: 202,
    );
    _lastRun = run['id'] as String?;
    final ids = {
      for (final job in run['jobs'] as List)
        (job as Map)['name']! as String: job['id']! as String,
    };
    final checkId = ids['Check dev for android']!;
    final buildId = ids['Build dev for android']!;
    final uploadId = ids['Upload dev for android']!;
    _lastJob = buildId;
    final upload = await _waitForJob(uploadId, const Duration(minutes: 30), {
      'succeeded',
      'failed',
      'cancelled',
      'waiting_for_approval',
    });
    if (upload['state'] != 'succeeded') {
      throw _Failure('the upload ${upload['state']}: ${upload['message']}');
    }

    // --- where the jobs ran
    final check = await _get('/jobs/$checkId');
    final build = await _get('/jobs/$buildId');
    _expect(
      check['state'] == 'succeeded' && check['runnerId'] == null,
      'the check ran on the engine: ${check['state']} ${check['runnerId']}',
    );
    _expect(
      build['state'] == 'succeeded' &&
          build['runnerId'] == identity['runnerId'],
      'the build ran on the runner ${identity['runnerId']}: '
      '${build['state']} ${build['runnerId']} ${build['message']}',
    );
    _expect(upload['runnerId'] == null, 'the upload ran on the engine');
    final steps = [for (final step in build['steps'] as List) step as Map];
    _expect(
      steps.map((s) => s['kind']).toList().toString() ==
              [
                'git.checkout',
                'version.bump',
                'build.android',
                'record.manifest',
              ].toString() &&
          steps.every((s) => s['state'] == 'succeeded'),
      'the build job ran its four steps: $steps',
    );
    final checkout = steps.first['result'] as Map;
    final remoteWorktree = checkout['path']! as String;
    _expect(
      remoteWorktree.startsWith(p.join(runnerData, 'source', 'worktrees')) &&
          !remoteWorktree.startsWith(data),
      'the checkout was made in a worktree of the runner: $remoteWorktree',
    );

    // --- what the runner uploaded
    final build_ = run['build']! as int;
    final artifacts =
        (await _get('/jobs/$buildId/artifacts'))['artifacts'] as List;
    Map<dynamic, dynamic> artifact(String kind) => artifacts.firstWhere(
      (a) => (a as Map)['kind'] == kind,
      orElse: () => throw _Failure('the build stored no $kind: $artifacts'),
    ) as Map;
    final apk = artifact('apk');
    final manifest = artifact('manifest');
    _expect(
      apk['name'] == 'dev-1.0.0+$build_.apk',
      'the APK is named for the version and build: ${apk['name']}',
    );
    final apkBytes = await _download('/artifacts/${apk['id']}/download');
    _expect(
      sha256OfBytes(apkBytes) == apk['sha256'] &&
          apkBytes.length == apk['size'] &&
          apkBytes[0] == 0x50 &&
          apkBytes[1] == 0x4b,
      'the APK in the engine store is the zip the runner uploaded, with the '
      'digest it declared',
    );
    final manifestText = utf8.decode(
      await _download('/artifacts/${manifest['id']}/download'),
    );
    _expect(
      manifestText.contains('"build": $build_') &&
          manifestText.contains('"sha256": "${apk['sha256']}"'),
      'the manifest the runner uploaded names the build and the APK',
    );
    final releases = _firebase!.apps[_firebaseAppId]!.releases;
    _expect(
      releases.length == 1 &&
          sha256OfBytes(releases.single.binary) == apk['sha256'] &&
          releases.single.buildVersion == '$build_',
      'Firebase received the APK the runner built, from the engine: $releases',
    );

    // --- what the runner left
    _expect(
      _secretFiles(runnerData).isEmpty,
      'no secret file is left on the runner',
    );
    final jobsFolder = Directory(p.join(runnerData, 'jobs'));
    _expect(
      !jobsFolder.existsSync() || jobsFolder.listSync().isEmpty,
      'no work folder is left on the runner',
    );
    final worktrees = Directory(p.join(runnerData, 'source', 'worktrees'));
    _expect(
      !worktrees.existsSync() ||
          worktrees.listSync(recursive: true).whereType<File>().isEmpty,
      'no worktree is left on the runner',
    );
    _expect(
      Directory(p.join(runnerData, 'source', 'mirrors')).listSync().length == 1,
      'the runner keeps one bare cache of the repository, keyed by its id',
    );
    _log(
      'the build job ran on the runner (${checkout['sha']}), the check and the '
      'upload on the engine; the APK in the engine store is the one the runner '
      'built and Firebase received it',
    );
  }

  // ------------------------------------------------------------- MCP gate

  /// Phase 13: an agent that dispatches a production release through
  /// `xp mcp` ends up at a pending approval that its token cannot decide.
  ///
  /// What is real: the engine, its database and gates, `xp connect` (tokens in
  /// the file secret store of a temporary config folder, never a Keychain),
  /// `xp mcp` as a child process speaking MCP JSON-RPC on standard input and
  /// output, and the `prod-release` workflow up to its first gate (which comes
  /// before any build, so nothing heavy runs). It checks that
  ///
  ///   - the MCP tool list has no tool to approve, deny, merge or change a
  ///     gate,
  ///   - the dispatched run stops at `waiting_for_approval` and the approval is
  ///     pending, as the MCP tools, the CLI and the HTTP API all see it,
  ///   - the MCP token gets 403 on approve, on deny and on loosening a gate,
  ///     and the approval is still pending afterwards,
  ///   - the app token approves it (the first decision wins) and the job goes
  ///     on, and the MCP tools then see it approved.
  Future<void> _mcpGate(String projectId) async {
    final xp = this.xp;
    if (xp == null) throw const _Failure('--xp is required for --mode mcp');
    final cliToken = await _createToken('cli', 'e2e cli');
    final mcpToken = await _createToken('mcp', 'e2e mcp');
    final environment = {
      for (final entry in Platform.environment.entries)
        if (!entry.key.startsWith('XP_')) entry.key: entry.value,
      'XP_CONFIG_DIR': p.join(work, 'xp-config'),
      // The tokens go to a file, not to the Keychain of this Mac.
      'XP_TEST_FILE_SECRETS': '1',
      'XP_NO_UPDATE_CHECK': '1',
    };

    Future<ProcessResult> runXp(List<String> arguments) async {
      final result = await Process.run(
        xp,
        arguments,
        environment: environment,
        includeParentEnvironment: false,
      );
      _log('xp ${arguments.first}... exited ${result.exitCode}');
      return result;
    }

    final connected = await runXp([
      'connect',
      _url.toString(),
      '--token',
      cliToken,
      '--mcp-token',
      mcpToken,
    ]);
    _expect(
      connected.exitCode == 0,
      'xp connect exits 0, not ${connected.exitCode}: ${connected.stderr}',
    );
    final listed = await runXp(['--json', 'projects', 'list']);
    _expect(
      listed.exitCode == 0 && '${listed.stdout}'.contains(projectId),
      'xp projects list (with the saved CLI token) shows the project: '
      '${listed.stdout}${listed.stderr}',
    );
    _log('xp connect saved the tokens; the CLI reads the project');

    // A named credential added and assigned with the CLI (ADR 0013); its
    // secret goes in on stdin, never in the arguments.
    const webhook = 'https://hooks.slack.com/services/T0/B0/E2ESECRET';
    final process = await Process.start(
      xp,
      [
        'credentials',
        'add',
        '--kind',
        'slack',
        '--name',
        'Team Slack · e2e',
        '--webhook-url-stdin',
      ],
      environment: environment,
      includeParentEnvironment: false,
    );
    final addOut = process.stdout.transform(utf8.decoder).join();
    final addErr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(webhook);
    await process.stdin.close();
    final addExit = await process.exitCode;
    _expect(
      addExit == 0 && !'${await addOut}${await addErr}'.contains('E2ESECRET'),
      'xp credentials add exits 0 and never prints the secret, not $addExit: '
      '${await addErr}',
    );
    final assigned = await runXp([
      'credentials',
      'assign',
      'team slack · e2e',
      '--project',
      projectId,
      '--flavor',
      'dev',
    ]);
    _expect(
      assigned.exitCode == 0,
      'xp credentials assign exits 0, not ${assigned.exitCode}: '
      '${assigned.stderr}',
    );
    _log('xp added a named Slack credential and assigned it to dev');

    final session = await _McpSession.start(xp, environment);
    try {
      final initialized = await session.request('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'mcp_gate_e2e', 'version': '1'},
      });
      session.notify('notifications/initialized');
      _expect(
        (initialized['serverInfo'] as Map)['name'] == 'xpath',
        'the MCP server introduces itself as xpath: $initialized',
      );

      final listing = await session.request('tools/list', {});
      final names = [
        for (final tool in listing['tools'] as List)
          (tool as Map)['name']! as String,
      ];
      for (final name in names) {
        for (final forbidden in [
          'approve',
          'deny',
          'merge',
          'abandon',
          'delete',
          'remove',
          'set_gates',
          'tighten',
        ]) {
          _expect(
            !name.contains(forbidden),
            'the tool $name offers $forbidden',
          );
        }
      }
      _expect(
        names.toSet().containsAll([
          'list_projects',
          'dispatch_workflow',
          'get_run',
          'get_approval',
        ]),
        'the MCP tools include dispatch and the approval poll: $names',
      );
      _log('xp mcp offers ${names.length} tools, none that approves');

      // Credentials are read-only to agents (ADR 0013): the MCP tool lists
      // them without a secret, and the MCP token cannot add one.
      _expect(
        names.contains('list_credentials') &&
            names
                .where((name) => name.contains('credential'))
                .every((name) => name == 'list_credentials'),
        'the only credential tool is list_credentials: $names',
      );
      final credentials = await session.toolList('list_credentials');
      _expect(
        '$credentials'.contains('Team Slack · e2e') &&
            '$credentials'.contains('dev') &&
            !'$credentials'.contains('E2ESECRET'),
        'list_credentials shows the credential, not its secret: $credentials',
      );
      await _call(
        'POST',
        '/credentials',
        {'name': 'Agent', 'kind': 'slack', 'webhookUrl': 'https://x'},
        expect: 403,
        token: mcpToken,
      );
      _log('the MCP token reads the credentials and cannot add one');

      final projects = await session.toolList('list_projects');
      _expect(
        projects.any((project) => (project as Map)['id'] == projectId),
        'the MCP tool list_projects shows the project',
      );

      final dispatched = await session.toolObject('dispatch_workflow', {
        'project': projectId,
        'workflow': 'prod-release',
        'platforms': ['android'],
        'flavors': ['prod'],
      });
      final runId =
          (dispatched['run'] as Map<String, dynamic>)['id']! as String;
      _lastRun = runId;
      _log('dispatched the production release through MCP: $runId');

      // The run stops at its first gate and says which approval it waits for.
      Map<dynamic, dynamic>? waiting;
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        final view = await session.toolObject('get_run', {'run': runId});
        final state = (view['run'] as Map)['state'];
        if (state == 'waiting_for_approval' &&
            (view['pendingApprovals'] as List).isNotEmpty) {
          waiting = view;
          break;
        }
        if (state == 'failed' || state == 'cancelled' || state == 'succeeded') {
          throw _Failure('the run is $state before it reached its gate');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (waiting == null) {
        throw const _Failure('the run did not stop at an approval in 5 min');
      }
      final approval =
          (waiting['pendingApprovals'] as List).first as Map<dynamic, dynamic>;
      final approvalId = approval['id']! as String;
      _expect(
        approval['action'] == 'prod_release' && approval['state'] == 'pending',
        'the run waits for a pending prod_release approval: $approval',
      );
      _log('the run waits for the pending approval $approvalId');

      final polled = await session.toolObject('get_approval', {
        'approval': approvalId,
      });
      _expect(polled['state'] == 'pending', 'MCP polls it as pending: $polled');
      final viaCli = await runXp([
        '--json',
        'approvals',
        'list',
        '--state',
        'pending',
      ]);
      _expect(
        viaCli.exitCode == 0 && '${viaCli.stdout}'.contains(approvalId),
        'xp approvals list shows it: ${viaCli.stdout}${viaCli.stderr}',
      );
      final viaRun = await runXp(['--json', 'runs', 'show', runId]);
      _expect(
        '${viaRun.stdout}'.contains('pendingApprovals') &&
            '${viaRun.stdout}'.contains(approvalId),
        'xp runs show names the approval: ${viaRun.stdout}',
      );

      // The MCP token cannot decide it, nor loosen the gate (D-13).
      final approve = await _call(
        'POST',
        '/approvals/$approvalId/approve',
        null,
        expect: 403,
        token: mcpToken,
      );
      _expect(
        (approve['error'] as Map)['code'] == 'forbidden',
        'approving with the MCP token is forbidden: $approve',
      );
      await _call(
        'POST',
        '/approvals/$approvalId/deny',
        null,
        expect: 403,
        token: mcpToken,
      );
      await _call(
        'PUT',
        '/projects/$projectId/gates',
        {
          'gates': {'prod_release': false},
        },
        expect: 403,
        token: mcpToken,
      );
      final still = await _get('/approvals/$approvalId');
      _expect(
        still['state'] == 'pending',
        'the approval is still pending after the MCP token tried: $still',
      );
      _log('the MCP token got 403 on approve, deny and loosening the gate');

      // The owner (an app token) approves; the job goes on.
      final decided = await _post('/approvals/$approvalId/approve', null);
      _expect(
        decided['state'] == 'approved' &&
            (decided['decidedBy'] as Map)['kind'] == 'app',
        'the app token approves it: $decided',
      );
      final after = await session.toolObject('get_approval', {
        'approval': approvalId,
      });
      _expect(after['state'] == 'approved', 'MCP sees it approved: $after');
      final jobs = (waiting['run'] as Map<String, dynamic>)['jobs'] as List;
      final jobId = (jobs.first as Map<String, dynamic>)['id']! as String;
      _lastJob = jobId;
      final resumed = await _waitForJob(jobId, const Duration(minutes: 2), {
        'running',
        'succeeded',
        'failed',
        'cancelled',
      });
      _log('after the approval the job is ${resumed['state']}');
      try {
        await _post('/runs/$runId/cancel', null);
      } on _Failure {
        // It may have ended on its own already.
      }
    } finally {
      await session.close();
    }
  }

  String _jobOf(Map<String, dynamic> run, int index) =>
      ((run['jobs'] as List)[index] as Map)['id']! as String;

  // ---------------------------------------------------------------- setup

  /// The bare repository the fake GitHub hands out as the clone URL, and a
  /// working clone whose `origin` looks like GitHub's.
  String _makeRepositories() {
    final clone = p.join(work, 'clone');
    _copy(Directory(fixture), Directory(clone));
    _git(['init', '--quiet', '-b', 'main'], clone);
    _git(['add', '--all'], clone);
    _git(['commit', '--quiet', '-m', 'fixture'], clone);
    final origin = p.join(work, 'origin.git');
    _git(['clone', '--quiet', '--bare', clone, origin], work);
    _git([
      'remote',
      'add',
      'origin',
      'https://github.com/e2e/build-app.git',
    ], clone);
    return origin;
  }

  void _git(List<String> arguments, String directory) {
    final result = Process.runSync('git', [
      '-c',
      'user.name=XPath e2e',
      '-c',
      'user.email=e2e@localhost',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: directory);
    if (result.exitCode != 0) {
      throw _Failure('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  /// Puts the Flutter SDK of this machine in the engine's cache under the
  /// version the fixture pins, unless a fvm of the machine finds it.
  void _linkFlutter() {
    final sdk = flutterSdk;
    if (sdk == null) return;
    final pin =
        (jsonDecode(File(p.join(fixture, '.fvmrc')).readAsStringSync())
                as Map<String, dynamic>)['flutter']!
            as String;
    final target = p.join(data, 'toolchains', 'flutter', pin);
    Directory(p.dirname(target)).createSync(recursive: true);
    Link(target).createSync(sdk);
  }

  late final Map<String, String> _engineEnvironment;

  Future<void> _startEngine() async {
    final environment = _engineEnvironment = {
      ...Platform.environment,
      TestEndpoints.githubApiVariable: _github!.url.toString(),
      TestEndpoints.firebaseVariable: _firebase!.baseUrl.toString(),
      TestEndpoints.fileSecretsVariable: '1',
      // A lease of 6 seconds: the runner fences its job 21 seconds after the
      // engine went quiet, not 105.
      if (mode == 'runner-offline') TestEndpoints.leaseSecondsVariable: '6',
      if (mode == 'runner-loss')
        // `keytool` accepts the made-up keystore the script saves.
        'PATH': '${_keytoolShim()}:${Platform.environment['PATH']}',
      if (mode == 'runner-build')
        // No fvm answers, so the engine takes the Flutter SDK of its cache
        // (its home folder is not the one fvm keeps its SDKs in).
        'PATH': '${_fvmShim()}:${Platform.environment['PATH']}',
      if (mode == 'prod') ...{
        TestEndpoints.ascVariable: _asc!.baseUrl.toString(),
        TestEndpoints.playVariable: _play!.baseUrl.toString(),
        // The shims come first, so that every program the engine starts by
        // name is looked up there.
        'PATH': '${p.join(work, 'shims')}:${Platform.environment['PATH']}',
      },
    };
    if (mode == 'runner-build') {
      // An engine that cannot build Android: no SDK in its environment, and a
      // home folder where Android Studio has put none.
      environment
        ..remove('ANDROID_HOME')
        ..remove('ANDROID_SDK_ROOT')
        ..['HOME'] = (Directory(
          p.join(work, 'engine-home'),
        )..createSync(recursive: true)).path;
    }
    // The GitHub CLI of the engine is a script that prints a made-up token.
    final gh = File(p.join(work, 'gh'))
      ..writeAsStringSync('#!/bin/sh\necho $_githubToken\n');
    Process.runSync('chmod', ['+x', gh.path]);
    final imported = await Process.run(xpd, [
      'secrets',
      'import-gh',
      '--data-dir',
      data,
      '--gh',
      gh.path,
    ], environment: environment);
    if (imported.exitCode != 0) {
      throw _Failure('xpd secrets import-gh failed: ${imported.stderr}');
    }
    final created = await Process.run(xpd, [
      'token',
      'create',
      '--data-dir',
      data,
      '--name',
      'e2e',
      '--kind',
      'app',
    ], environment: environment);
    if (created.exitCode != 0) {
      throw _Failure('xpd token create failed: ${created.stderr}');
    }
    _token = (created.stdout as String).trim();
    await _launchEngine();
  }

  /// Starts `xpd serve` on [port] (any free one for 0) and waits until it
  /// listens.
  Future<void> _launchEngine({int port = 0}) async {
    final engine = _engine = await Process.start(
      xpd,
      [
        'serve',
        '--port',
        '$port',
        '--data-dir',
        data,
        '--slots',
        // One slot for the runner tests: a long job on the engine keeps the
        // next ones for the runner.
        if (mode == 'runner-loss' || mode == 'runner-offline') '1' else '2',
      ],
      environment: _engineEnvironment,
      includeParentEnvironment: mode != 'runner-build',
    );
    final listening = Completer<Uri>();
    engine.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _engineLog.writeln(line);
          final match = RegExp(r'http://\S+').firstMatch(line);
          if (match != null && !listening.isCompleted) {
            listening.complete(Uri.parse(match[0]!));
          }
        });
    engine.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_engineLog.writeln);
    unawaited(
      engine.exitCode.then((code) {
        if (!listening.isCompleted) {
          listening.completeError(_Failure('xpd exited with $code'));
        }
      }),
    );
    _url = await listening.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const _Failure('xpd did not start in 60 s'),
    );
    _log('xpd is listening on $_url');
  }

  // -------------------------------------------------------- production flow

  /// A production release of the fixture, from `draft` to `merged`, through
  /// the engine over HTTP only, with these fakes (all on loopback):
  ///
  ///   - App Store Connect, with an API key, and its iTunes lookup,
  ///   - Google Play, with a service account,
  ///   - Firebase App Distribution (the fixture's prod flavor is not a
  ///     Shorebird flavor, so the release makes no call to it; it is there to
  ///     prove that),
  ///   - GitHub: the repository, pull requests (create, find, read, merge) and
  ///     a real merge commit in the bare repository that plays `origin`.
  ///
  /// What is real: the engine process, its SQLite database, its git mirror,
  /// worktrees, tag and push, `flutter build appbundle` (a real AAB, built
  /// with Gradle), the upload to the fake Play, the polling of the fake stores
  /// and the merge. What is faked, because this machine has no signing
  /// identity and Apple has no fake: `flutter build ipa` (a wrapper around the
  /// SDK writes a placeholder IPA) and `xcrun altool` (a shim that prints what
  /// a successful upload prints). Both are PATH shims or an SDK wrapper in the
  /// work folder; the engine runs unchanged.
  ///
  /// It checks that the release walks `draft`, `building`, `uploaded`,
  /// `in_review`, `approved`, `live`, `merged`; that the tag is
  /// `v<x.y.z>+<build>` on the tip of the release branch in the fake origin
  /// and reachable from the base branch after the merge commit; that the
  /// merge went through the approval gate and used a merge commit; that the
  /// folder of the owner is unchanged; and that no secret is in a stored log,
  /// the database or the arguments of any process the engine started.
  Future<void> _prod(Map<String, dynamic> project) async {
    final projectId = project['id']! as String;
    // The scan finds the flavors of the fixture in Gradle, so it cannot tell
    // which iOS bundle id belongs to the prod flavor (the Xcode project has
    // one for the app): the owner says so, as the app's profile editor would.
    const iosBundleId = 'ly.abdurahman.xpath.buildApp';
    final edited = await _call('PATCH', '/projects/$projectId', {
      'apps': [
        {
          'path': '.',
          'flavors': [
            {'name': 'prod', 'iosBundleId': iosBundleId},
          ],
        },
      ],
    });
    final profile = edited['profile']! as Map<String, dynamic>;
    final app = (profile['apps']! as List).single as Map<String, dynamic>;
    final prod = (app['flavors']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((flavor) => flavor['name'] == 'prod');
    final bundleId = prod['iosBundleId'] as String?;
    final androidId = prod['androidAppId'] as String?;
    _expect(
      bundleId == iosBundleId && androidId != null,
      'the prod flavor has the iOS bundle id $iosBundleId and an Android '
      'application id, not $bundleId and $androidId',
    );
    await _listenToEvents();

    // The stores know the app, and have seen build 41 on Play and 40 on App
    // Store Connect: the build number of the release is the next one (D-11).
    const appleAppId = '1234567890';
    _asc!
      ..addApp(bundleId!, id: appleAppId)
      ..addBuild(appleAppId, buildNumber: '40', version: '0.9.0');
    final appleVersion = _asc!.addVersion(appleAppId, '1.0.0');
    final playApp = _play!.addApp(androidId!)..addRelease('internal', [41]);

    await _addCredential(
      projectId,
      flavor: 'prod',
      name: 'App Store Connect · e2e',
      fields: {
        'kind': 'asc_key',
        'keyId': fakeAscKeyId,
        'issuerId': fakeAscIssuerId,
        'privateKey': fakeAscPrivateKeyPem,
        'keyKind': 'team',
      },
    );
    await _addCredential(
      projectId,
      flavor: 'prod',
      name: 'Play publisher · e2e',
      fields: {
        'kind': 'play_sa',
        'serviceAccount': _play!.serviceAccountJson(),
      },
    );
    _log(
      'added the App Store Connect key and the Play service account, '
      'assigned to prod and checked for its bundle id and package',
    );

    final workflows = await _get('/projects/$projectId/workflows');
    final byName = {
      for (final workflow in workflows['workflows'] as List)
        (workflow as Map)['name']! as String: workflow['id']! as String,
    };
    _expect(
      byName.keys.toSet().containsAll(['prod-release', 'release-merge']),
      'the built-in workflows include prod-release and release-merge',
    );

    // ---- dispatch: draft
    final run = await _post(
      '/projects/$projectId/workflows/${byName['prod-release']}/dispatch',
      {
        'platforms': ['android', 'ios'],
        'flavors': ['prod'],
        'inputs': {
          'appleAppIds': {'prod': appleAppId},
          'playTrack': 'internal',
        },
      },
      expect: 202,
    );
    final runId = run['id']! as String;
    final build = run['build']! as int;
    final version = run['version']! as String;
    _expect(
      version == '1.0.0' && build == 42,
      'the release is 1.0.0 with the build after 41 and 40, not '
      '$version+$build',
    );
    // The fake Play cannot read the manifest of the real bundle.
    _play!.uploadVersionCode = build;
    final tag = 'v$version+$build';
    final releases = (await _get('/releases'))['releases'] as List;
    _expect(releases.length == 1, 'dispatch made one release: $releases');
    final releaseId = (releases.single as Map)['id']! as String;
    var release = await _get('/releases/$releaseId');
    _expect(
      release['state'] == 'draft' &&
          release['version'] == version &&
          release['build'] == build &&
          _storeStates(release).values.every((s) => s == 'pending') &&
          _storeStates(release).keys.toSet().containsAll(['apple', 'play']),
      'the release is a draft that targets Apple and Play: $release',
    );
    _log('dispatched run $runId: release $releaseId is a draft of $tag');

    // ---- build, upload, tag, push, pull request (the owner approves the
    // release and the push, as an app does)
    final approvals = <Map<String, dynamic>>[];
    await _driveRun(runId, const Duration(minutes: 30), approvals, {
      'prod_release',
      'push',
    });
    _expect(
      approvals.map((a) => a['action']).toList().toString() ==
          ['prod_release', 'push'].toString(),
      'the release asked for the owner approval of prod_release, then push: '
      '${approvals.map((a) => a['action'])}',
    );
    _expect(
      approvals.every((a) => a['version'] == '$version+$build'),
      'both approvals are bound to $version+$build',
    );
    release = await _waitForRelease(releaseId, {'uploaded'});
    final head = release['headSha']! as String;
    _expect(
      release['tag'] == tag &&
          release['branch'] == 'release/$version' &&
          release['baseBranch'] == 'main' &&
          release['prNumber'] == 1 &&
          '${release['prUrl']}'.endsWith('/pull/1') &&
          _storeStates(release).values.every((s) => s == 'uploaded'),
      'the release is uploaded, tagged, on its branch and has its pull '
      'request: $release',
    );
    _expect(
      _originGit(['rev-parse', '$tag^{commit}']) == head &&
          _originGit(['rev-parse', 'refs/heads/release/$version']) == head,
      'the tag $tag and the release branch name the same commit in the '
      'origin, $head',
    );
    final pull = _github!.pulls[1]!;
    _expect(
      pull.head == 'release/$version' && pull.base == 'main' && pull.open,
      'the fake GitHub has one open pull request from the release branch',
    );
    final artifacts =
        ((await _get('/jobs/${_buildJobs(run).first}/artifacts'))['artifacts']
                as List)
            .map((a) => (a as Map)['kind'])
            .toSet();
    _log('uploaded; artifacts of a build job: $artifacts');

    // The Play side of the upload: a real bundle, and the commit that never
    // cancels a review (D-15).
    final commits = _play!.commits;
    _expect(
      commits.length == 1 &&
          commits.single.changesInReviewBehavior == 'ERROR_IF_IN_REVIEW' &&
          playApp.bundles.containsKey(build),
      'Play got version code $build in one commit that cannot cancel a '
      'review: $commits',
    );

    // ---- the stores review it: in_review, approved, live
    appleVersion.appVersionState = 'WAITING_FOR_REVIEW';
    release = await _refreshTo(releaseId, 'in_review');
    appleVersion.appVersionState = 'IN_REVIEW';
    release = await _refreshTo(releaseId, 'in_review');
    _expect(
      _storeStates(release)['apple'] == 'in_review' &&
          _storeStates(release)['play'] == 'in_review',
      'both stores review it: ${_storeStates(release)}',
    );
    appleVersion.appVersionState = 'PENDING_DEVELOPER_RELEASE';
    release = await _refreshTo(releaseId, 'in_review');
    playApp.tracks['internal']!.single.lifecycleState =
        'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED';
    release = await _refreshTo(releaseId, 'approved');
    appleVersion.appVersionState = 'READY_FOR_DISTRIBUTION';
    release = await _refreshTo(releaseId, 'approved');
    _expect(
      _storeStates(release)['apple'] == 'live' &&
          _storeStates(release)['play'] == 'approved' &&
          release['mergeEnabled'] == false,
      'Apple is live and Play is not: the merge stays closed: $release',
    );
    playApp.tracks['internal']!.single.lifecycleState =
        'RELEASE_LIFECYCLE_STATE_PUBLISHED';
    release = await _refreshTo(releaseId, 'live');
    _expect(
      release['mergeEnabled'] == true &&
          _storeStates(release).values.every((s) => s == 'live'),
      'every store is live, so the merge is open: $release',
    );

    // ---- the merge: gated, approved by the app, never by an agent
    final merge = await _post('/releases/$releaseId/merge', null, expect: 202);
    final mergeRun = merge['id']! as String;
    await _waitForRunState(mergeRun, 'waiting_for_approval');
    final pending =
        ((await _get('/approvals?state=pending'))['approvals'] as List)
            .cast<Map<String, dynamic>>();
    _expect(
      pending.length == 1 &&
          pending.single['action'] == 'merge' &&
          pending.single['version'] == '$version+$build' &&
          pending.single['sha'] == head,
      'the merge waits for the owner, bound to $version+$build on $head: '
      '$pending',
    );
    _expect(
      (await _get('/releases/$releaseId'))['state'] == 'live',
      'the pull request is not merged before the owner approves',
    );
    final agent = await _agentToken();
    final refused = await _call(
      'POST',
      '/approvals/${pending.single['id']}/approve',
      null,
      expect: 403,
      token: agent,
    );
    _log('an mcp token cannot approve the merge: ${refused['error']}');
    _expect(
      _github!.mergeBodies.isEmpty,
      'nothing was merged before the approval',
    );
    approvals.clear();
    await _driveRun(mergeRun, const Duration(minutes: 5), approvals, {'merge'});
    release = await _waitForRelease(releaseId, {'merged'});
    _log('merged: ${release['mergeCommit']}');

    // ---- the merge used a merge commit, on the commit that was released
    final body = _github!.mergeBodies.single;
    _expect(
      body['merge_method'] == 'merge' && body['sha'] == head,
      'GitHub was asked for a merge commit of $head: $body',
    );
    final merged = release['mergeCommit']! as String;
    final parents = _originGit(['rev-list', '--parents', '-n', '1', merged])
        .split(' ');
    _expect(
      parents.length == 3 && parents[2] == head,
      'the merge commit $merged has the release tip $head as its second '
      'parent: $parents',
    );
    _expect(
      _originGit(['rev-parse', 'refs/heads/main']) == merged,
      'main points at the merge commit',
    );
    _expect(
      Process.runSync('git', [
            '-C',
            _github!.origin,
            'merge-base',
            '--is-ancestor',
            tag,
            'main',
          ]).exitCode ==
          0,
      'the tag $tag is reachable from main after the merge',
    );
    _expect(
      _github!.unauthorized == 0,
      'every call to GitHub carried the imported token',
    );
    _expect(
      _firebase!.apps.values.every((app) => app.releases.isEmpty),
      'a production release of a flavor without Shorebird makes no call to '
      'Firebase App Distribution',
    );

    // ---- the events a client follows
    await _stopListening();
    final types = _events.map((e) => e.event.type).toList();
    for (final type in [
      'release.created',
      'release.state_changed',
      'release.store_changed',
      'approval.requested',
      'approval.decided',
    ]) {
      _expect(types.contains(type), 'the event log has $type: $types');
    }
    final states = [
      for (final e in _events)
        if (e.event case ReleaseStateChanged(:final to)) to.wire,
    ];
    _expect(
      _inOrder(states, [
        'building',
        'uploaded',
        'in_review',
        'approved',
        'live',
        'merged',
      ]),
      'the release events walk the states in order: $states',
    );

    // ---- the owner's folder, and the secrets
    final after = _SourceSnapshot.of(p.join(work, 'clone'));
    final changes = _sourceBefore.differences(after);
    _expect(
      changes.isEmpty,
      'the source folder is unchanged (status, HEAD, refs and the hash of '
      'every file); it changed: $changes',
    );
    _log(
      'the source folder is unchanged: ${after.hashes.length} files hashed, '
      'HEAD ${after.head.substring(0, 12)}, git status clean',
    );
    _checkNoSecrets();
  }

  /// The ids of the build jobs of [run].
  List<String> _buildJobs(Map<String, dynamic> run) => [
    for (final job in run['jobs'] as List)
      if ('${(job as Map)['name']}'.startsWith('Build')) job['id']! as String,
  ];

  Map<String, String> _storeStates(Map<String, dynamic> release) => {
    for (final store in release['stores'] as List)
      (store as Map)['store']! as String: store['state']! as String,
  };

  bool _inOrder(List<String> seen, List<String> wanted) {
    var at = 0;
    for (final state in seen) {
      if (at < wanted.length && state == wanted[at]) at++;
    }
    return at == wanted.length;
  }

  /// Runs the run to its end the way the app would: whenever it waits for
  /// the owner, the pending approvals are approved with an app token, and
  /// each is recorded in [approved]. A pending approval of an action that is
  /// not in [allowed] fails the check.
  Future<void> _driveRun(
    String id,
    Duration timeout,
    List<Map<String, dynamic>> approved,
    Set<String> allowed,
  ) async {
    _lastRun = id;
    final deadline = DateTime.now().add(timeout);
    var last = '';
    while (DateTime.now().isBefore(deadline)) {
      final run = await _get('/runs/$id');
      final state = run['state']! as String;
      if (state != last) {
        last = state;
        _log('run $id is $state');
      }
      if (state == 'succeeded') return;
      if (state == 'failed' || state == 'cancelled') {
        throw _Failure('run $id $state');
      }
      if (state == 'waiting_for_approval') {
        final pending =
            (await _get('/approvals?state=pending'))['approvals'] as List;
        for (final entry in pending) {
          final approval = (entry as Map).cast<String, dynamic>();
          final action = approval['action']! as String;
          _expect(
            allowed.contains(action),
            'run $id asked for the approval of $action, not one of $allowed',
          );
          _log('approving $action of ${approval['version']}');
          await _post('/approvals/${approval['id']}/approve', {
            'reason': 'release_e2e',
          });
          approved.add(approval);
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw _Failure('run $id did not end in $timeout');
  }

  Future<void> _waitForRunState(String id, String wanted) async {
    _lastRun = id;
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final run = await _get('/runs/$id');
      if (run['state'] == wanted) return;
      if (run['state'] == 'failed' || run['state'] == 'cancelled') {
        throw _Failure('run $id ${run['state']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _Failure('run $id did not reach $wanted');
  }

  /// The release once it is in one of [states].
  Future<Map<String, dynamic>> _waitForRelease(
    String id,
    Set<String> states,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var release = <String, dynamic>{};
    while (DateTime.now().isBefore(deadline)) {
      release = await _get('/releases/$id');
      if (states.contains(release['state'])) {
        _log('release $id is ${release['state']}');
        return release;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _Failure(
      'release $id is ${release['state']}, not ${states.join('/')}',
    );
  }

  /// Asks the stores now (the manual refresh) and checks that the release is
  /// in [state] afterwards.
  Future<Map<String, dynamic>> _refreshTo(String id, String state) async {
    final release = await _post('/releases/$id/refresh', null);
    _expect(
      release['state'] == state,
      'after the refresh the release is $state, not ${release['state']} '
      '(${_storeStates(release)})',
    );
    _log('refreshed: $state ${_storeStates(release)}');
    return release;
  }

  String _originGit(List<String> arguments) {
    final result = Process.runSync('git', [
      '-C',
      _github!.origin,
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      throw _Failure('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  /// A token of the `mcp` kind, as an agent has.
  Future<String> _agentToken() => _createToken('mcp', 'agent');

  /// A new device token of [kind], printed once by `xpd token create`.
  Future<String> _createToken(String kind, String name) async {
    final created = await Process.run(xpd, [
      'token',
      'create',
      '--data-dir',
      data,
      '--name',
      name,
      '--kind',
      kind,
    ], environment: _engineEnvironment);
    if (created.exitCode != 0) {
      throw _Failure('xpd token create failed: ${created.stderr}');
    }
    return (created.stdout as String).trim();
  }

  Future<void> _listenToEvents() async {
    final socket = await WebSocket.connect(
      _url.replace(scheme: 'ws', path: '/events', query: 'after=0').toString(),
      headers: {'authorization': 'Bearer $_token'},
    );
    _eventSocket = socket
      ..listen(
        (frame) => _events.add(
          SequencedEvent.fromJson(
            jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        ),
      );
  }

  Future<void> _stopListening() async {
    // Let the last frames arrive.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _eventSocket?.close();
    _eventSocket = null;
  }

  // ---------------------------------------------------------- the shims

  /// Where `perl` is on the machine, `git`, `xcrun`: the programs the shims
  /// stand in front of.
  /// A folder with an `fvm` that always fails.
  String _fvmShim() {
    final directory = Directory(p.join(work, 'runner-shims'))
      ..createSync(recursive: true);
    final file = File(p.join(directory.path, 'fvm'))
      ..writeAsStringSync('#!/bin/sh\nexit 1\n');
    Process.runSync('chmod', ['+x', file.path]);
    return directory.path;
  }

  /// A folder with a `keytool` that accepts any keystore, for the engine to
  /// check the made-up one with.
  String _keytoolShim() {
    final directory = Directory(p.join(work, 'keytool-shim'))
      ..createSync(recursive: true);
    final file = File(p.join(directory.path, 'keytool'))
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', ['+x', file.path]);
    return directory.path;
  }

  String _real(String name) {
    for (final directory in Platform.environment['PATH']!.split(':')) {
      final candidate = File(p.join(directory, name));
      if (candidate.existsSync()) return candidate.path;
    }
    throw _Failure('$name is not on PATH');
  }

  /// Writes the scripts the engine finds first on its PATH (`<work>/shims`):
  ///
  ///   - `perl` and `git` log the arguments of every call and run the real
  ///     program. Every process a step starts goes through the `perl`
  ///     trampoline that puts it in its own process group (ADR 0003), so the
  ///     log has the arguments of all of them (`flutter`, `gradle` through it,
  ///     `xcrun`, ...), and every git call of the engine goes through `git`.
  ///     The log is the file `argv.log` of the work folder.
  ///   - `xcrun` logs, and answers `altool` the way a successful upload
  ///     does; it runs the real `xcrun` for anything else. (Faked: there is
  ///     no Apple to upload to.)
  ///   - `fvm` fails, so that the engine takes the Flutter SDK that was put
  ///     in its cache instead of one of fvm's.
  void _writeShims() {
    final directory = Directory(p.join(work, 'shims'))
      ..createSync(recursive: true);
    File(_argvLog).writeAsStringSync('');
    void shim(String name, String script) {
      final file = File(p.join(directory.path, name))
        ..writeAsStringSync('#!/bin/sh\n$script');
      Process.runSync('chmod', ['+x', file.path]);
    }

    String log(String name) => "printf '$name %s\\n' \"\$*\" >> '$_argvLog'\n";
    shim('perl', "${log('perl')}exec '${_real('perl')}' \"\$@\"\n");
    shim('git', "${log('git')}exec '${_real('git')}' \"\$@\"\n");
    shim('fvm', 'exit 1\n');
    shim(
      'xcrun',
      '${log('xcrun')}'
          'if [ "\$1" = altool ]; then\n'
          '  echo "release_e2e: this stands in for xcrun altool"\n'
          '  echo "No errors uploading the package."\n'
          '  echo "UPLOAD SUCCEEDED with no errors"\n'
          '  echo "Delivery UUID: 123e4567-e89b-12d3-a456-426614174000"\n'
          '  exit 0\n'
          'fi\n'
          "exec '${_real('xcrun')}' \"\$@\"\n",
    );
  }

  /// Puts a Flutter SDK in the cache of the engine that runs everything with
  /// the real one but `flutter build ipa`, which it answers with a
  /// placeholder IPA. (Faked: building an IPA needs a signing identity.)
  void _wrapFlutter() {
    final sdk = flutterSdk;
    if (sdk == null) {
      throw const _Failure('--flutter-sdk is needed to run the prod flow');
    }
    final pin =
        (jsonDecode(File(p.join(fixture, '.fvmrc')).readAsStringSync())
                as Map<String, dynamic>)['flutter']!
            as String;
    final bin = Directory(p.join(data, 'toolchains', 'flutter', pin, 'bin'))
      ..createSync(recursive: true);
    final script = File(p.join(bin.path, 'flutter'))
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'case " \$* " in\n'
        '  *" build ipa "*)\n'
        '    echo "release_e2e: no signing identity here: this stands in for '
        'flutter build ipa"\n'
        '    mkdir -p build/ios/ipa\n'
        '    echo "not a real IPA (release_e2e)" > build/ios/ipa/build_app.ipa\n'
        '    exit 0 ;;\n'
        'esac\n'
        "exec '${p.join(sdk, 'bin', 'flutter')}' \"\$@\"\n",
      );
    Process.runSync('chmod', ['+x', script.path]);
  }

  // ----------------------------------------------------------- the secrets

  /// Checks that none of the secrets of the fakes is in a stored log, the
  /// SQLite database, the log of the engine, a file the engine left in its
  /// temporary folder, or the arguments of a process (`argv.log`).
  void _checkNoSecrets() {
    final haystacks = <String, String>{};
    void add(File file) {
      if (file.existsSync()) {
        haystacks[file.path] = latin1.decode(file.readAsBytesSync());
      }
    }

    for (final directory in ['logs', 'tmp']) {
      final folder = Directory(p.join(data, directory));
      if (folder.existsSync()) {
        folder.listSync(recursive: true).whereType<File>().forEach(add);
      }
    }
    for (final suffix in ['', '-wal', '-shm']) {
      add(File(p.join(data, '$databaseFileName$suffix')));
    }
    add(File(_argvLog));
    haystacks['(output of the engine)'] = _engineLog.toString();

    final logs = haystacks.keys.where((path) => path.contains('/logs/'));
    final argv = haystacks[_argvLog]!;
    _expect(
      logs.isNotEmpty && argv.contains('altool'),
      'there are logs and a record of the arguments to scan',
    );
    final needles = <String, String>{
      'the GitHub token': _githubToken,
      'a device token': _token,
      for (final (name, pem) in [
        ('the App Store Connect key', fakeAscPrivateKeyPem),
        ('the Google service account key', fakePlayPrivateKeyPem),
      ]) ...{
        name: _pemBody(pem),
        for (final (i, line) in _pemLines(pem).indexed) '$name (line $i)': line,
      },
    };
    for (final MapEntry(key: name, value: needle) in needles.entries) {
      for (final MapEntry(key: where, value: text) in haystacks.entries) {
        _expect(!text.contains(needle), '$name is in $where');
      }
    }
    final bytes = haystacks.values.fold<int>(
      0,
      (sum, text) => sum + text.length,
    );
    _log(
      'no secret in ${haystacks.length} places (${logs.length} stored logs, '
      'the database, the arguments of '
      '${LineSplitter.split(argv).length} process starts, the output of the '
      'engine; $bytes characters)',
    );
  }

  List<String> _pemLines(String pem) => [
    for (final line in LineSplitter.split(pem))
      if (!line.startsWith('-----') && line.trim().length >= 30) line.trim(),
  ];

  String _pemBody(String pem) => _pemLines(pem).join();

  // ---------------------------------------------------------------- HTTP

  /// Adds a named credential (`POST /credentials`) and assigns it to the
  /// flavor [flavor] of the root app (ADR 0013); the assignment must be
  /// accepted for the flavor. Returns the id of the credential.
  Future<String> _addCredential(
    String projectId, {
    required String flavor,
    required String name,
    required Map<String, Object?> fields,
  }) async {
    final created = await _call('POST', '/credentials', {
      'name': name,
      ...fields,
    }, expect: 201);
    final id = created['id']! as String;
    final kind = fields['kind']! as String;
    final assigned = await _call(
      'PUT',
      '/projects/$projectId/flavors/$flavor/credentials/$kind',
      {'credentialId': id},
    );
    final statuses = [
      for (final credential in assigned['assigned'] as List)
        (credential as Map)['status'],
    ];
    _expect(
      statuses.length == 1 && statuses.single == 'verified',
      'the $kind credential "$name" is accepted for $flavor, not $statuses',
    );
    return id;
  }

  Future<Map<String, dynamic>> _get(String path) => _call('GET', path, null);

  Future<Map<String, dynamic>> _post(
    String path,
    Object? body, {
    int expect = 200,
  }) => _call('POST', path, body, expect: expect);

  Future<Map<String, dynamic>> _put(String path, Object body) =>
      _call('PUT', path, body, expect: 201);

  Future<Map<String, dynamic>> _call(
    String method,
    String path,
    Object? body, {
    int expect = 200,
    String? token,
  }) async {
    final request = await _client.openUrl(method, _url.resolve(path));
    request.headers.set('authorization', 'Bearer ${token ?? _token}');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode != expect) {
      throw _Failure(
        '$method $path answered ${response.statusCode}, not $expect: $text',
      );
    }
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<List<int>> _download(String path) async {
    final request = await _client.getUrl(_url.resolve(path));
    request.headers.set('authorization', 'Bearer $_token');
    final response = await request.close();
    final bytes = await response.expand((chunk) => chunk).toList();
    if (response.statusCode != 200) {
      throw _Failure('GET $path answered ${response.statusCode}');
    }
    return bytes;
  }

  Future<Map<String, dynamic>> _waitForJob(
    String id,
    Duration timeout,
    Set<String> states,
  ) async {
    final deadline = DateTime.now().add(timeout);
    var last = '';
    while (DateTime.now().isBefore(deadline)) {
      final job = await _get('/jobs/$id');
      if (job['state'] != last) {
        last = job['state']! as String;
        _log('job $id is $last');
      }
      if (states.contains(last)) return job;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw _Failure('job $id did not reach ${states.join(' or ')} in $timeout');
  }

  // --------------------------------------------------------------- finish

  /// Prints what helps to find out why a check failed.
  Future<void> explain() async {
    if (_runnerLog.isNotEmpty) {
      stderr.writeln('--- output of the runner:\n$_runnerLog');
    }
    final id = _lastJob;
    if (id != null && _engine != null) await _explainJob(id);
    final run = _lastRun;
    if (run != null && _engine != null) {
      try {
        final state = await _get('/runs/$run');
        stderr.writeln('--- run $run: ${state['state']}');
        for (final job in state['jobs'] as List) {
          final j = (job as Map).cast<String, dynamic>();
          stderr.writeln('  ${j['name']}: ${j['state']} ${j['message'] ?? ''}');
          if (j['state'] == 'failed') {
            _lastJob = j['id'] as String;
            await _explainJob(j['id'] as String);
          }
        }
      } on Object catch (error) {
        stderr.writeln('(could not read the run: $error)');
      }
    }
    stderr
      ..writeln('--- engine log')
      ..write(_engineLog);
  }

  Future<void> _explainJob(String id) async {
    try {
      final job = await _get('/jobs/$id');
      stderr.writeln('--- job $id: ${job['state']} ${job['message'] ?? ''}');
      for (final step in job['steps'] as List) {
        final s = step as Map;
        final message = s['message'] ?? '';
        stderr.writeln(
          '  ${s['ordinal']} ${s['kind']}: ${s['state']} $message',
        );
      }
      final logs = Directory(p.join(data, 'logs', id));
      if (logs.existsSync()) {
        for (final file in logs.listSync().whereType<File>()) {
          final lines = file.readAsLinesSync();
          stderr.writeln('--- ${p.basename(file.path)} (last 30 lines)');
          for (final line in lines.skip(
            lines.length > 30 ? lines.length - 30 : 0,
          )) {
            stderr.writeln('  ${(jsonDecode(line) as Map)['text']}');
          }
        }
      }
    } on Object catch (error) {
      stderr.writeln('(could not read the job: $error)');
    }
  }

  Future<void> stop() async {
    _client.close(force: true);
    _runnerProcess?.kill(ProcessSignal.sigkill);
    final engine = _engine;
    if (engine != null) {
      engine.kill();
      await engine.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          engine.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
    }
    await _eventSocket?.close();
    await _firebase?.close();
    await _asc?.close();
    await _play?.close();
    await _github?.close();
  }

  void _expect(bool condition, String what) {
    if (!condition) throw _Failure('check failed: $what');
  }
}

/// `xp mcp` as a child process, spoken to in MCP JSON-RPC (one JSON message
/// per line on standard input and output).
class _McpSession {
  new _(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }

  /// Starts `xp mcp` with [environment].
  static Future<_McpSession> start(
    String xp,
    Map<String, String> environment,
  ) async => _McpSession._(
    await Process.start(
      xp,
      ['mcp'],
      environment: environment,
      includeParentEnvironment: false,
    ),
  );

  final Process _process;
  final _stderr = StringBuffer();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 1;

  void _onLine(String line) {
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      // Standard output must carry MCP messages only.
      for (final pending in _pending.values) {
        pending.completeError(
          _Failure('xp mcp wrote something that is not JSON: $line'),
        );
      }
      return;
    }
    final id = message['id'];
    if (id is int) _pending.remove(id)?.complete(message);
  }

  void _send(Map<String, Object?> message) =>
      _process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...message}));

  /// Sends a request and returns its `result`.
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = _nextId++;
    final answer = _pending[id] = Completer();
    _send({'id': id, 'method': method, 'params': params});
    final message = await answer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () =>
          throw _Failure('xp mcp did not answer $method: $_stderr'),
    );
    if (message['error'] != null) {
      throw _Failure('xp mcp answered $method with ${message['error']}');
    }
    return message['result'] as Map<String, dynamic>;
  }

  /// Sends a notification.
  void notify(String method) => _send({'method': method});

  /// Calls a tool whose text is a JSON object.
  Future<Map<String, dynamic>> toolObject(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async => (await tool(name, arguments))! as Map<String, dynamic>;

  /// Calls a tool whose text is a JSON list.
  Future<List<dynamic>> toolList(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async => (await tool(name, arguments))! as List<dynamic>;

  /// Calls a tool and returns what its text says, decoded from JSON.
  Future<Object?> tool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final result = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final text =
        (((result['content'] as List).single) as Map)['text']! as String;
    if (result['isError'] == true) {
      throw _Failure('the MCP tool $name failed: $text');
    }
    return jsonDecode(text);
  }

  /// Ends the session: closing standard input ends `xp mcp`.
  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }
}

/// Copies [from] to [to] without build output and tool caches.
void _copy(Directory from, Directory to) {
  const skipped = {'build', '.dart_tool', '.gradle', '.idea'};
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = p.basename(entity.path);
    if (skipped.contains(name) || name == 'local.properties') continue;
    final target = p.join(to.path, name);
    if (entity is Directory) {
      _copy(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

void _log(String message) => stderr.writeln('e2e: $message');

/// What a folder holds, to prove that a run left it alone: the hash of every
/// file of the working tree (not `.git`), `HEAD`, every ref and `git status`.
class _SourceSnapshot {
  const new(this.hashes, this.head, this.refs, this.status);

  factory of(String directory) {
    String git(List<String> arguments) {
      final result = Process.runSync('git', ['-C', directory, ...arguments]);
      if (result.exitCode != 0) {
        throw _Failure('git ${arguments.join(' ')} failed: ${result.stderr}');
      }
      return (result.stdout as String).trim();
    }

    final hashes = <String, String>{};
    for (final entity in Directory(directory).listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: directory);
      if (entity is! File || p.split(relative).first == '.git') continue;
      hashes[relative] = sha256OfBytes(entity.readAsBytesSync());
    }
    return _SourceSnapshot(
      hashes,
      git(['rev-parse', 'HEAD']),
      git(['for-each-ref']),
      git(['status', '--porcelain', '--ignored']),
    );
  }

  final Map<String, String> hashes;
  final String head;
  final String refs;
  final String status;

  /// What differs from [other], in words.
  List<String> differences(_SourceSnapshot other) => [
    if (head != other.head) 'HEAD ${other.head}',
    if (refs != other.refs) 'refs:\n${other.refs}',
    if (other.status.isNotEmpty) 'git status:\n${other.status}',
    for (final path in {...hashes.keys, ...other.hashes.keys})
      if (hashes[path] != other.hashes[path]) path,
  ];
}

/// A pull request of [_FakeGitHub].
class _PullRequest {
  new(this.number, this.title, this.head, this.base);

  final int number;
  final String title;
  final String head;
  final String base;
  bool open = true;
  String? mergeCommit;
}

/// A fake GitHub on a loopback port: the repository by name and by id, and
/// the pull requests of the release flow (create, find, read, merge). It
/// answers 401 to a call without the token, and keeps the bare repository
/// `origin` that plays the remote: a merge makes a real merge commit in it.
class _FakeGitHub {
  new _(this._server, this.origin, this.token);

  static Future<_FakeGitHub> start(
    String origin, {
    required String token,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final github = _FakeGitHub._(server, origin, token);
    server.listen(github._handle);
    return github;
  }

  final HttpServer _server;

  /// The bare repository.
  final String origin;

  /// The token the engine must send.
  final String token;

  /// Every request as `METHOD path`, oldest first.
  final requests = <String>[];

  /// The body of every merge request.
  final mergeBodies = <Map<String, dynamic>>[];

  /// The pull requests, by number.
  final pulls = <int, _PullRequest>{};

  /// How many calls came without the token.
  int unauthorized = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    final body = text.isEmpty ? null : jsonDecode(text);
    final path = request.uri.path;
    requests.add('${request.method} $path');
    final (
      status,
      json,
    ) = request.headers.value('authorization') == 'Bearer $token'
        ? _route(
            request.method,
            request.uri.pathSegments,
            request.uri.queryParameters,
            body as Map<String, dynamic>?,
          )
        : (401, {'message': 'Bad credentials'}).also(() => unauthorized++);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(json));
    await request.response.close();
  }

  (int, Object) _route(
    String method,
    List<String> path,
    Map<String, String> query,
    Map<String, dynamic>? body,
  ) {
    switch ((method, path)) {
      case ('GET', ['repos', 'e2e', 'build-app']) ||
          ('GET', ['repositories', '$_repoId']):
        return (
          200,
          {
            'id': _repoId,
            'full_name': 'e2e/build-app',
            'default_branch': 'main',
            'clone_url': origin,
          },
        );
      case ('GET', ['repos', 'e2e', 'build-app', 'pulls']):
        return (
          200,
          [
            for (final pull in pulls.values)
              if (pull.open &&
                  query['head'] == 'e2e:${pull.head}' &&
                  query['base'] == pull.base)
                _json(pull),
          ],
        );
      case ('POST', ['repos', 'e2e', 'build-app', 'pulls']):
        final head = body!['head']! as String;
        final base = body['base']! as String;
        if (_git(['rev-parse', '--verify', 'refs/heads/$head']) == null) {
          return (
            422,
            {
              'message': 'Validation Failed',
              'errors': [
                {'message': 'No commits between $base and $head'},
              ],
            },
          );
        }
        final pull = pulls[pulls.length + 1] = _PullRequest(
          pulls.length + 1,
          body['title']! as String,
          head,
          base,
        );
        return (201, _json(pull));
      case ('GET', ['repos', 'e2e', 'build-app', 'pulls', final number]):
        final pull = pulls[int.parse(number)];
        return pull == null ? _notFound : (200, _json(pull));
      case (
        'PUT',
        ['repos', 'e2e', 'build-app', 'pulls', final number, 'merge'],
      ):
        final pull = pulls[int.parse(number)];
        if (pull == null) return _notFound;
        mergeBodies.add(body!);
        if (!pull.open) {
          return (405, {'message': 'Pull Request is not mergeable'});
        }
        if (body['merge_method'] != 'merge') {
          return (
            405,
            {'message': 'Only merge commits are allowed on this repository.'},
          );
        }
        final tip = _git(['rev-parse', 'refs/heads/${pull.head}'])!;
        if (body['sha'] != null && body['sha'] != tip) {
          return (
            409,
            {'message': 'Head branch was modified. Review and try again.'},
          );
        }
        final main = _git(['rev-parse', 'refs/heads/${pull.base}'])!;
        final merge = _git([
          'commit-tree',
          '$tip^{tree}',
          '-p',
          main,
          '-p',
          tip,
          '-m',
          'Merge pull request #${pull.number} from e2e/${pull.head}',
        ])!;
        _git(['update-ref', 'refs/heads/${pull.base}', merge, main]);
        pull
          ..open = false
          ..mergeCommit = merge;
        return (
          200,
          {
            'merged': true,
            'sha': merge,
            'message': 'Pull Request successfully merged',
          },
        );
      default:
        return _notFound;
    }
  }

  static const _repoId = 4242;
  static const (int, Object) _notFound = (404, {'message': 'Not Found'});

  Map<String, Object?> _json(_PullRequest pull) => {
    'number': pull.number,
    'title': pull.title,
    'state': pull.open ? 'open' : 'closed',
    'merged': pull.mergeCommit != null,
    'html_url': 'https://github.com/e2e/build-app/pull/${pull.number}',
    'head': {
      'ref': pull.head,
      'sha': _git(['rev-parse', 'refs/heads/${pull.head}']),
    },
    'base': {'ref': pull.base},
    'merge_commit_sha': pull.mergeCommit,
  };

  /// The output of `git` in the bare repository, or `null` if it failed.
  String? _git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      ['-C', origin, ...arguments],
      environment: {
        'GIT_AUTHOR_NAME': 'GitHub',
        'GIT_AUTHOR_EMAIL': 'noreply@github.com',
        'GIT_COMMITTER_NAME': 'GitHub',
        'GIT_COMMITTER_EMAIL': 'noreply@github.com',
      },
    );
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  }
}

extension on (int, Object) {
  /// This value, after running [action].
  (int, Object) also(void Function() action) {
    action();
    return this;
  }
}
