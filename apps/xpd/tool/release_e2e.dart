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
// Usage: dart run tool/release_e2e.dart --mode dev|prod --xpd <executable>
//          --fixture <dir> --work <dir> [--flutter-sdk <dir>]
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
    ..addOption('mode', allowed: ['dev', 'prod'], defaultsTo: 'dev')
    ..addOption('xpd', mandatory: true, help: 'The xpd executable.')
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
    required this.fixture,
    required this.work,
    required this.flutterSdk,
  }) : data = p.join(work, 'data');

  final String mode;
  final String xpd;
  final String fixture;
  final String work;
  final String? flutterSdk;
  final String data;

  FakeFirebaseServer? _firebase;
  _FakeGitHub? _github;
  FakeAscServer? _asc;
  FakePlayServer? _play;
  Process? _engine;
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
    if (mode == 'prod') {
      await _prod(project);
      return;
    }

    await _put('/projects/$projectId/credentials', {
      'app': '.',
      'flavor': 'dev',
      'kind': 'firebase_sa',
      'serviceAccount': _firebase!.serviceAccountJson(),
    });
    _log('saved the Firebase service account for dev');

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
    _expect(jobs.length == 1, 'dev-build for android is one job: $jobs');
    final jobId = (jobs.single as Map)['id']! as String;
    _lastJob = jobId;
    _log('dispatched run ${run['id']} (build ${run['build']}), job $jobId');

    final job = await _waitForJob(jobId, const Duration(minutes: 25), {
      'succeeded',
      'failed',
      'cancelled',
      'waiting_for_approval',
    });
    if (job['state'] != 'succeeded') {
      throw _Failure('the dev build ${job['state']}: ${job['message']}');
    }
    final kinds = [
      for (final step in job['steps'] as List) (step as Map)['kind'],
    ];
    _log('steps: $kinds');

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
      if (mode == 'prod') ...{
        TestEndpoints.ascVariable: _asc!.baseUrl.toString(),
        TestEndpoints.playVariable: _play!.baseUrl.toString(),
        // The shims come first, so that every program the engine starts by
        // name is looked up there.
        'PATH': '${p.join(work, 'shims')}:${Platform.environment['PATH']}',
      },
    };
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

    final engine = _engine = await Process.start(xpd, [
      'serve',
      '--port',
      '0',
      '--data-dir',
      data,
      '--slots',
      '2',
    ], environment: environment);
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

    await _put('/projects/$projectId/credentials', {
      'app': '.',
      'flavor': 'prod',
      'kind': 'asc_key',
      'keyId': fakeAscKeyId,
      'issuerId': fakeAscIssuerId,
      'privateKey': fakeAscPrivateKeyPem,
      'keyKind': 'team',
    });
    await _put('/projects/$projectId/credentials', {
      'app': '.',
      'flavor': 'prod',
      'kind': 'play_sa',
      'serviceAccount': _play!.serviceAccountJson(),
    });
    _log('saved the App Store Connect key and the Play service account');

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
  Future<String> _agentToken() async {
    final created = await Process.run(xpd, [
      'token',
      'create',
      '--data-dir',
      data,
      '--name',
      'agent',
      '--kind',
      'mcp',
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
