import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_command.dart';
import 'package:xp/src/runner/runner_doctor.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';
import '../../helpers/test_env.dart';

const _ok = ProcessOutput(exitCode: 0);
const _notFound = ProcessOutput(exitCode: 127, stderr: 'sh: java: not found');

/// A machine that answers the probe and the doctor's own commands. [has]
/// names what is installed: `git`, `tools` (curl, unzip, xz), `sdk`, `java`,
/// `perl`, `ssh`, `swift`, and for Linux iOS builds `omarchy` (a checkout at
/// the pin), `darwin-sdk` and `ios-tools`.
class _Machine {
  new(this.has);

  final Set<String> has;
  ProcessOutput ssh = const ProcessOutput(
    exitCode: 1,
    stderr:
        "Hi octo! You've successfully authenticated, but GitHub does not "
        'provide shell access.\n',
  );
  ProcessOutput df = const ProcessOutput(
    exitCode: 0,
    stdout:
        'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
        '/dev/sda1 104857600 0 52428800 50% /\n',
  );
  final calls = <String>[];

  /// What an executable answers instead, or throws.
  final answers = <String, ProcessOutput Function()>{};

  ProcessOutput answer(FakeProcessCall call) {
    calls.add(call.executable);
    if (answers[call.executable] case final answer?) return answer();
    final script = call.arguments.length == 2 ? call.arguments[1] : '';
    switch (call.executable) {
      case 'uname':
        return const ProcessOutput(exitCode: 0, stdout: 'Linux\n');
      case 'sh' when script == RunnerProbe.flutterToolsScript:
        return has.contains('tools')
            ? _ok
            : const ProcessOutput(exitCode: 1, stdout: 'xz\n');
      case 'sh' when script == RunnerProbe.androidSdkScript:
        return has.contains('sdk') ? _ok : const ProcessOutput(exitCode: 1);
      case 'git' when call.arguments.contains('rev-parse'):
        return has.contains('omarchy')
            ? const ProcessOutput(
                exitCode: 0,
                stdout: '${RunnerProbe.iosLinuxPin}\n',
              )
            : const ProcessOutput(
                exitCode: 128,
                stderr: 'fatal: not a git repository\n',
              );
      case 'sh' when script == RunnerProbe.darwinSdkScript:
        return has.contains('darwin-sdk')
            ? _ok
            : const ProcessOutput(exitCode: 1);
      case 'sh' when script == RunnerProbe.iosLinuxToolsScript:
        return has.contains('ios-tools')
            ? _ok
            : const ProcessOutput(exitCode: 1, stdout: 'rcodesign\n');
      case 'sh' when script == RunnerProbe.javaScript:
        return has.contains('java')
            ? const ProcessOutput(
                exitCode: 0,
                stderr: 'openjdk version "17.0.12" 2024-07-16\n',
              )
            : _notFound;
      case 'ssh' when !has.contains('ssh'):
        throw const ProcessStartException('ssh', 'not found');
      case 'ssh':
        return ssh;
      case 'df':
        return df;
      case final executable when has.contains(executable):
        return _ok;
      case final executable:
        throw ProcessStartException(executable, 'not found');
    }
  }
}

void main() {
  late Directory directory;
  late RunnerPaths paths;
  late MemorySecretStore credentials;
  late _Machine machine;
  late TestEnv env;

  RunnerHost host({Map<String, String>? environment}) => RunnerHost(
    operatingSystem: 'linux',
    cores: 8,
    pid: 1,
    environment: environment ?? {'HOME': directory.path},
    runner: FakeProcessRunner(machine.answer),
    openCredentials: (_) => credentials,
  );

  RunnerDoctor doctor({
    Future<ServiceStatus> Function()? service,
    List<String> gitHosts = const ['github.com'],
    Map<String, String>? environment,
  }) => RunnerDoctor(
    host: host(environment: environment),
    paths: paths,
    clientFactory: env.context.clientFactory,
    serviceStatus:
        service ??
        () async => const ServiceStatus(
          path: '/unit',
          installed: false,
          loaded: false,
          running: false,
        ),
    gitHosts: gitHosts,
  );

  Future<DoctorCheck> check(String name, [RunnerDoctor? with_]) async =>
      (await (with_ ?? doctor()).examine()).checks.firstWhere(
        (check) => check.name == name,
      );

  Future<void> enroll() => RunnerEnrollments(paths, credentials).write(
    RunnerEnrollment(
      identity: RunnerIdentity(
        engine: Uri.parse('http://engine:7480'),
        runnerId: 'rnr_1',
        name: 'aws',
      ),
      credential: 'xpr_credential',
    ),
  );

  setUp(() {
    env = TestEnv();
    directory = Directory.systemTemp.createTempSync('xp_runner_doctor_');
    addTearDown(() {
      env.dispose();
      directory.deleteSync(recursive: true);
    });
    paths = RunnerPaths('${directory.path}/runner');
    credentials = MemorySecretStore();
    machine = _Machine({'git', 'tools', 'sdk', 'perl', 'ssh'});
  });

  group('capabilities', () {
    test('a box without a JDK misses android and offers flutter', () async {
      final report = await doctor().examine();

      final android = report.checks.firstWhere((c) => c.name == 'android');
      expect(android.state, DoctorState.missing);
      expect(android.detail, 'no JDK: java not found');
      expect(android.fix, startsWith('install JDK 17'));
      expect(
        report.checks.firstWhere((c) => c.name == 'flutter').state,
        DoctorState.ok,
      );
      expect(report.checks.map((c) => c.name), isNot(contains('ios-sign')));
      expect(report.ready, isTrue);
    });

    test('joins the reasons when a capability lacks two things', () async {
      machine.has.remove('sdk');

      final android = await check('android');

      expect(android.detail, contains('no Android SDK'));
      expect(android.detail, contains('; no JDK: java not found'));
      expect(android.fix, contains('; install JDK 17'));
    });

    test('lists ios-linux only on a runner configured for it', () async {
      machine.has.addAll({'swift', 'omarchy', 'darwin-sdk', 'ios-tools'});

      final unconfigured = await doctor().examine();
      final configured = await doctor(
        environment: {
          'HOME': directory.path,
          iosLinuxDirectoryVariable: '/srv/omarchy',
        },
      ).examine();

      expect(
        unconfigured.checks.map((c) => c.name),
        isNot(contains('ios-linux')),
      );
      final iosLinux = configured.checks.firstWhere(
        (c) => c.name == 'ios-linux',
      );
      expect(iosLinux.state, DoctorState.ok);
    });

    test('says what a configured runner lacks for ios-linux, with the '
        'fixes', () async {
      machine.has.add('swift');

      final iosLinux = await check(
        'ios-linux',
        doctor(
          environment: {
            'HOME': directory.path,
            iosLinuxDirectoryVariable: '/srv/omarchy',
          },
        ),
      );

      expect(iosLinux.state, DoctorState.missing);
      expect(
        iosLinux.detail,
        '/srv/omarchy is not an omarchy-apple-dev checkout: fatal: not a git '
        'repository; no darwin SDK bundle (swift-sdks/darwin.artifactbundle '
        r'under $XDG_CONFIG_HOME/swiftpm or ~/.swiftpm); no rcodesign: '
        'omarchy-apple-dev needs it',
      );
      expect(iosLinux.fix, startsWith('git clone https://github.com/'));
      expect(iosLinux.fix, contains('; download Xcode.xip in a browser'));
    });

    test('an empty XP_IOS_LINUX_DIR is no configuration', () async {
      final report = await doctor(
        environment: {'HOME': directory.path, iosLinuxDirectoryVariable: ''},
      ).examine();

      expect(report.checks.map((c) => c.name), isNot(contains('ios-linux')));
    });

    test('a box with nothing is not ready', () async {
      machine.has.removeAll({'git', 'sdk'});

      final report = await doctor().examine();

      expect(report.ready, isFalse);
    });
  });

  group('perl', () {
    test('is found, or says what the runner needs it for', () async {
      expect((await check('perl')).state, DoctorState.ok);

      machine.has.remove('perl');
      final missing = await check('perl');

      expect(missing.state, DoctorState.missing);
      expect(missing.detail, 'perl not found');
      expect(missing.fix, contains('apt-get install perl'));
    });

    test('that fails or hangs is missing', () async {
      machine.answers['perl'] = () => const ProcessOutput(exitCode: 2);
      expect((await check('perl')).detail, 'perl exited with 2');

      machine.answers['perl'] = () => throw TimeoutException('slow');
      expect((await check('perl')).detail, 'perl did not answer in time');
    });
  });

  group('pairing and the engine', () {
    test('an unpaired runner skips the engine and says so', () async {
      final paired = await check('paired');
      final engine = await check('engine');

      expect(paired.state, DoctorState.missing);
      expect(paired.detail, '${paths.root} has no runner.json');
      expect(paired.fix, contains('xp runners pair <name>'));
      expect(engine.state, DoctorState.skipped);
      expect(engine.detail, contains('not paired'));
    });

    test('a paired runner asks the engine for its version', () async {
      await enroll();
      when(() => env.client.version()).thenAnswer(
        (_) async => const VersionResponse(version: '1.1.2', apiVersion: '1'),
      );

      final paired = await check('paired');
      final engine = await check('engine');

      expect(paired.state, DoctorState.ok);
      expect(paired.detail, 'as "aws" (rnr_1) of http://engine:7480');
      expect(engine.state, DoctorState.ok);
      expect(engine.detail, 'http://engine:7480 runs 1.1.2');
    });

    test(
      'an engine of another API or that does not answer is missing',
      () async {
        await enroll();
        when(() => env.client.version()).thenAnswer(
          (_) async => const VersionResponse(version: '2.0.0', apiVersion: '2'),
        );
        final other = await check('engine');
        expect(other.state, DoctorState.missing);
        expect(other.fix, 'install the xp of the engine, 2.0.0');

        when(() => env.client.version())
            .thenThrow(const ConnectionException('Connection refused.'));
        final away = await check('engine');
        expect(away.detail, contains('does not answer: Connection refused.'));
        expect(away.fix, contains('#reaching-the-engine'));

        when(() => env.client.version())
            .thenAnswer((_) => Future.error(TimeoutException('slow')));
        expect(
          (await check('engine')).detail,
          contains('no answer within 10 seconds'),
        );
        when(() => env.client.version()).thenThrow(StateError('odd'));
        expect((await check('engine')).detail, contains('Bad state: odd'));
      },
    );

    test('a runner.json without its credential is not paired', () async {
      Directory(paths.root).createSync(recursive: true);
      File(paths.identityFile).writeAsStringSync(
        jsonEncode(
          RunnerIdentity(
            engine: Uri.parse('http://engine:7480'),
            runnerId: 'rnr_1',
            name: 'aws',
          ).toJson(),
        ),
      );

      expect(
        (await check('paired')).detail,
        'runner.json is there, its credential is not',
      );

      File(paths.identityFile).writeAsStringSync('[]');
      expect(
        (await check('paired')).detail,
        startsWith('runner.json cannot be read: '),
      );
    });

    test('a credential that cannot be read says whose it is', () async {
      await enroll();
      credentials.failure = const SecretStoreException('locked');

      final paired = await check('paired');

      expect(paired.detail, 'the credential cannot be read: locked');
      expect(paired.fix, contains('the user the runner runs as'));
    });
  });

  group('the service', () {
    Future<DoctorCheck> service(Future<ServiceStatus> Function() status) =>
        check('service', doctor(service: status));

    test('running is ok, not installed is skipped with the fix', () async {
      final running = await service(
        () async => const ServiceStatus(
          path: '/unit',
          installed: true,
          loaded: true,
          running: true,
          pid: 42,
        ),
      );
      expect(running.state, DoctorState.ok);
      expect(running.detail, 'running (pid 42)');

      final absent = await check('service');
      expect(absent.state, DoctorState.skipped);
      expect(absent.fix, contains('xp runner install-service'));
    });

    test(
      'installed and stopped is missing; a broken manager is skipped',
      () async {
        final stopped = await service(
          () async => const ServiceStatus(
            path: '/unit',
            installed: true,
            loaded: true,
            running: false,
            detail: 'failed',
          ),
        );
        expect(stopped.state, DoctorState.missing);
        expect(stopped.detail, 'installed, not running: failed');

        final quiet = await service(
          () async => const ServiceStatus(
            path: '/unit',
            installed: true,
            loaded: false,
            running: false,
          ),
        );
        expect(quiet.detail, 'installed, not running');

        final broken = await service(
          () => throw const ServiceException('no systemd'),
        );
        expect(broken.state, DoctorState.skipped);
        expect(broken.detail, contains('no systemd'));

        final running = await service(
          () async => const ServiceStatus(
            path: '/unit',
            installed: true,
            loaded: true,
            running: true,
          ),
        );
        expect(running.detail, 'running');
      },
    );
  });

  group('ssh', () {
    test('reads the greeting, not the exit code', () async {
      final github = await check('ssh github.com');
      expect(github.state, DoctorState.ok);
      expect(github.detail, startsWith('Hi octo!'));

      machine.ssh = const ProcessOutput(
        exitCode: 0,
        stdout: 'authenticated via ssh key.\n',
      );
      expect(
        (await check(
          'ssh bitbucket.org',
          doctor(gitHosts: ['bitbucket.org']),
        )).state,
        DoctorState.ok,
      );
    });

    test('without a key it says how to make one', () async {
      machine.ssh = const ProcessOutput(
        exitCode: 255,
        stderr: 'git@github.com: Permission denied (publickey).\n',
      );

      final ssh = await check('ssh github.com');

      expect(ssh.state, DoctorState.missing);
      expect(ssh.detail, 'git@github.com: Permission denied (publickey).');
      expect(ssh.fix, contains('ssh-keygen -t ed25519'));
    });

    test('with a key it says which one to add', () async {
      machine.ssh = const ProcessOutput(exitCode: 255);
      final key = File('${directory.path}/.ssh/id_rsa.pub')
        ..createSync(recursive: true);

      final ssh = await check('ssh github.com');

      expect(ssh.detail, 'ssh exited with 255');
      expect(
        ssh.fix,
        'add ${key.path} as a deploy key of the repository on '
        'github.com',
      );
    });

    test('an unknown host key, no ssh, or no answer', () async {
      machine.ssh = const ProcessOutput(
        exitCode: 255,
        stderr: 'Host key verification failed.\n',
      );
      expect(
        (await check('ssh github.com')).fix,
        'accept the key of github.com once: ssh -T git@github.com',
      );

      machine.has.remove('ssh');
      expect(
        (await check('ssh github.com')).fix,
        contains('apt-get install openssh-client'),
      );

      machine.answers['ssh'] = () => throw TimeoutException('slow');
      expect(
        (await check('ssh github.com')).detail,
        'github.com did not answer in time',
      );
    });
  });

  group('disk', () {
    test('compares the free space with what the capabilities need', () async {
      final enough = await check('disk');
      expect(enough.state, DoctorState.ok);
      expect(enough.detail, '50 GB free in ${directory.path}');

      machine.df = const ProcessOutput(
        exitCode: 0,
        stdout:
            'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
            '/dev/sda1 104857600 0 2097152 98% /\n',
      );
      final tight = await check('disk');
      expect(tight.state, DoctorState.missing);
      expect(
        tight.detail,
        '2 GB free in ${directory.path}; what this runner offers needs '
        'about 3 GB',
      );
    });

    test('counts about 7 GB for ios-linux', () async {
      machine
        ..has.addAll({'swift', 'omarchy', 'darwin-sdk', 'ios-tools'})
        ..df = const ProcessOutput(
          exitCode: 0,
          stdout:
              'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
              '/dev/sda1 104857600 0 10485760 90% /\n',
        );

      final disk = await check(
        'disk',
        doctor(
          environment: {
            'HOME': directory.path,
            iosLinuxDirectoryVariable: '/srv/omarchy',
          },
        ),
      );

      expect(disk.state, DoctorState.missing);
      expect(disk.detail, endsWith('needs about 12 GB'));
    });

    test('skips what df does not say', () async {
      machine.df = const ProcessOutput(exitCode: 1, stderr: 'df: no');
      expect((await check('disk')).state, DoctorState.skipped);

      machine.answers['df'] = () =>
          throw const ProcessStartException('df', 'not found');
      expect((await check('disk')).state, DoctorState.skipped);
    });
  });

  group('xp runner doctor', () {
    late CommandRunner<int> commands;

    setUp(() {
      commands = CommandRunner<int>('xp', 'test')
        ..argParser.addFlag('json')
        ..addCommand(runnerCommand(env.context, host: host()));
    });

    test('prints one line per check, then the fix, and exits 0 when '
        'something is offered', () async {
      final code = await commands.run([
        'runner',
        'doctor',
        '--data-dir',
        paths.root,
      ]);

      expect(code, 0);
      final out = env.logger.out;
      expect(out, contains('ok       flutter\n'));
      expect(out, contains('missing  android: no JDK: java not found\n'));
      expect(out, contains('         Install JDK 17 (apt-get install'));
      expect(out, contains('skipped  engine: not paired'));
      expect(out, endsWith('This runner can take jobs.'));
    });

    test('exits 1 when the runner can take no job', () async {
      machine.has.removeAll({'git', 'sdk'});

      final code = await commands.run([
        'runner',
        'doctor',
        '--data-dir',
        paths.root,
      ]);

      expect(code, 1);
      expect(
        env.logger.out,
        endsWith('This runner offers nothing, so it will get no jobs.'),
      );
    });

    test('--json prints the same checks', () async {
      final code = await commands.run([
        '--json',
        'runner',
        'doctor',
        '--data-dir',
        paths.root,
        '--git-host',
        'bitbucket.org',
      ]);

      expect(code, 0);
      final json = jsonDecode(env.logger.out) as Map<String, dynamic>;
      expect(json['ready'], isTrue);
      final checks = (json['checks'] as List).cast<Map<String, dynamic>>();
      expect(checks.firstWhere((c) => c['name'] == 'flutter'), {
        'name': 'flutter',
        'state': 'ok',
      });
      expect(
        checks.map((c) => c['name']),
        containsAll([
          'android',
          'perl',
          'paired',
          'engine',
          'service',
          'ssh bitbucket.org',
          'disk',
        ]),
      );
    });

    test('takes no positional argument', () async {
      await expectLater(
        commands.run(['runner', 'doctor', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
