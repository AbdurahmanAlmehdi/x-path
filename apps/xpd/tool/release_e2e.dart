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
// Usage: dart run tool/release_e2e.dart --mode dev --xpd <executable>
//          --fixture <dir> --work <dir> [--flutter-sdk <dir>]
//
// Exits 0 only if everything held; progress goes to standard error.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xpd/xpd.dart';

const _firebaseAppId = '1:684690133351:android:b434734f585770367c1fc2';
const _githubRepoId = 4242;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('mode', allowed: ['dev'], defaultsTo: 'dev')
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
    required this.xpd,
    required this.fixture,
    required this.work,
    required this.flutterSdk,
  }) : data = p.join(work, 'data');

  final String xpd;
  final String fixture;
  final String work;
  final String? flutterSdk;
  final String data;

  FakeFirebaseServer? _firebase;
  HttpServer? _github;
  Process? _engine;
  late Uri _url;
  late String _token;
  final _engineLog = StringBuffer();
  final _client = HttpClient();
  String? _lastJob;

  // ------------------------------------------------------------------- run

  Future<void> run() async {
    Directory(work).createSync(recursive: true);
    final origin = _makeRepositories();
    _firebase =
        await FakeFirebaseServer.start(
            pollsBeforeDone: 0,
            readVersionFromFileName: true,
          )
          ..addApp('684690133351', _firebaseAppId, groups: {'testers'});
    _github = await _startGitHub(origin);
    _linkFlutter();
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

    // Nothing approves a gate in this phase, so the first release stops at
    // its gate and keeps the project.
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

  /// A fake GitHub: the repository by name and by id, nothing else.
  Future<HttpServer> _startGitHub(String origin) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final repo = jsonEncode({
      'id': _githubRepoId,
      'full_name': 'e2e/build-app',
      'default_branch': 'main',
      'clone_url': origin,
    });
    server.listen((request) async {
      final path = request.uri.path;
      final known =
          path == '/repos/e2e/build-app' ||
          path == '/repositories/$_githubRepoId';
      request.response
        ..statusCode = known ? 200 : 404
        ..headers.contentType = ContentType.json
        ..write(known ? repo : jsonEncode({'message': 'Not Found'}));
      await request.response.close();
    });
    return server;
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

  Future<void> _startEngine() async {
    final environment = {
      ...Platform.environment,
      TestEndpoints.githubApiVariable: 'http://127.0.0.1:${_github!.port}',
      TestEndpoints.firebaseVariable: _firebase!.baseUrl.toString(),
      TestEndpoints.fileSecretsVariable: '1',
    };
    // The GitHub CLI of the engine is a script that prints a made-up token.
    final gh = File(p.join(work, 'gh'))
      ..writeAsStringSync('#!/bin/sh\necho ghp_e2e_made_up_token\n');
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
  }) async {
    final request = await _client.openUrl(method, _url.resolve(path));
    request.headers.set('authorization', 'Bearer $_token');
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
    if (id != null && _engine != null) {
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
    stderr
      ..writeln('--- engine log')
      ..write(_engineLog);
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
    await _firebase?.close();
    await _github?.close(force: true);
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
