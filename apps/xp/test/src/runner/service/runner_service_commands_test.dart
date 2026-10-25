@Tags(['process'])
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/runner_command.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/service/runner_service.dart';
import 'package:xp/src/version.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/bundle_fixtures.dart';
import '../../../helpers/memory_secret_store.dart';
import '../../../helpers/test_env.dart';

/// Runs `cp` for real (the command copies the bundle) and fakes the rest: no
/// test touches `launchctl` or `systemctl`.
class _Machine implements ProcessRunner {
  new(this.fake);

  final FakeProcessRunner fake;
  final real = const IoProcessRunner();

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => (executable == 'cp' ? real : fake).start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

void main() {
  late TestEnv env;
  late Directory directory;
  late String home;
  late RunnerPaths paths;
  late MemorySecretStore credentials;
  late FakeProcessRunner services;
  late Directory bundle;
  late CommandRunner<int> commands;
  String? launchctlPrint;

  RunnerHost hostOn(
    String operatingSystem, {
    String? executable,
    Map<String, String> environment = const {},
  }) => RunnerHost(
    operatingSystem: operatingSystem,
    cores: 8,
    pid: 1,
    environment: {'HOME': home, 'USER': 'me', ...environment},
    runner: _Machine(services),
    openCredentials: (_) => credentials,
    executable: executable ?? p.join(bundle.path, 'bin', 'xp'),
  );

  void use(RunnerHost host) {
    commands = CommandRunner<int>('xp', 'test')
      ..addCommand(runnerCommand(env.context, host: host));
  }

  Future<int> run(List<String> arguments) async {
    try {
      return await commands.run(['runner', ...arguments]) ?? 0;
    } on UsageException {
      return 64;
    }
  }

  Future<void> pair() => RunnerEnrollments(paths, credentials).write(
    RunnerEnrollment(
      identity: RunnerIdentity(
        engine: Uri.parse('http://engine:7480'),
        runnerId: 'rnr_1',
        name: 'mac-mini',
      ),
      credential: 'xpr_credential',
    ),
  );

  List<String> calls() => [
    for (final call in services.calls)
      [call.executable, ...call.arguments].join(' '),
  ];

  String plist() => p.join(
    home,
    'Library',
    'LaunchAgents',
    'ly.abdurahman.xpath.runner.plist',
  );

  String unit() =>
      p.join(home, '.config', 'systemd', 'user', 'xp-runner.service');

  setUp(() {
    env = TestEnv();
    directory = Directory.systemTemp.createTempSync('xp_runner_service_');
    addTearDown(() {
      env.dispose();
      directory.deleteSync(recursive: true);
    });
    home = p.join(directory.path, 'home');
    paths = RunnerPaths(p.join(directory.path, 'runner'));
    credentials = MemorySecretStore();
    bundle = writeBundle(directory, version: packageVersion);
    launchctlPrint = null;
    services = FakeProcessRunner((call) {
      if (call.executable == 'id') {
        return const ProcessOutput(exitCode: 0, stdout: '501\n');
      }
      if (call.executable == 'launchctl' && call.arguments.first == 'print') {
        return launchctlPrint == null
            ? const ProcessOutput(exitCode: 113)
            : ProcessOutput(exitCode: 0, stdout: launchctlPrint!);
      }
      if (call.executable == 'systemctl' && call.arguments.contains('show')) {
        return const ProcessOutput(
          exitCode: 0,
          stdout:
              'LoadState=loaded\nActiveState=active\nSubState=running\n'
              'MainPID=9\nUnitFileState=enabled\n',
        );
      }
      if (call.executable == 'loginctl') {
        return const ProcessOutput(exitCode: 0, stdout: 'Linger=yes\n');
      }
      return const ProcessOutput(exitCode: 0);
    });
    use(hostOn('macos'));
  });

  group('install-service on macOS', () {
    test(
      'installs the bundle, points current at it and loads the LaunchAgent',
      () async {
        await pair();

        final code = await run(['install-service', '--data-dir', paths.root]);

        expect(code, XpExit.ok, reason: env.logger.errors.join('\n'));
        expect(
          File(p.join(paths.versionDirectory(packageVersion), 'bin', 'xp'))
              .existsSync(),
          isTrue,
        );
        expect(
          Link(paths.currentLink).targetSync(),
          p.join('versions', packageVersion),
        );
        final text = File(plist()).readAsStringSync();
        expect(text, contains('<string>ly.abdurahman.xpath.runner</string>'));
        expect(text, contains('<string>${paths.currentExecutable}</string>'));
        for (final argument in ['runner', 'start', '--data-dir', paths.root]) {
          expect(text, contains('<string>$argument</string>'));
        }
        expect(
          text,
          contains('<key>XP_RUNNER_MANAGED</key>\n    <string>1</string>'),
        );
        expect(text, contains('/opt/homebrew/bin'));
        expect(text, contains('<integer>600</integer>'));
        expect(text, contains('${paths.serviceLogs}/runner.out.log'));
        expect(calls(), contains('launchctl bootstrap gui/501 ${plist()}'));
        final out = env.logger.out;
        expect(
          out,
          contains('Installed the runner service (ly.abdurahman.xpath.runner)'),
        );
        expect(out, contains('updates itself'));
        expect(out, contains('xp runner service-status'));
      },
    );

    test('passes the slots on, and a PATH of its own', () async {
      await pair();

      final code = await run([
        'install-service',
        '--data-dir',
        paths.root,
        '--slots',
        '3',
        '--path',
        '/a:/b',
      ]);

      expect(code, XpExit.ok, reason: env.logger.errors.join('\n'));
      final text = File(plist()).readAsStringSync();
      expect(text, contains('<string>--slots</string>'));
      expect(text, contains('<string>3</string>'));
      expect(text, contains('<string>/a:/b</string>'));
    });

    test('does not need the version to be installed twice', () async {
      await pair();
      await run(['install-service', '--data-dir', paths.root]);
      services.calls.clear();

      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.ok);
      expect(calls().where((call) => call.startsWith('cp')), isEmpty);
    });

    test('wants a runner that is paired', () async {
      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.config);
      expect(env.logger.errors.single, contains('is not paired'));
      expect(File(plist()).existsSync(), isFalse);
      expect(Directory(paths.versions).existsSync(), isFalse);
    });

    test('wants an xp that is an installed bundle', () async {
      use(hostOn('macos', executable: '/sdk/bin/dart'));
      await pair();

      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.config);
      expect(env.logger.errors.single, contains('is not an installed bundle'));
      expect(File(plist()).existsSync(), isFalse);
    });

    test('says so when it cannot tell where xp is', () async {
      use(hostOn('macos', executable: ''));
      await pair();

      expect(
        await run(['install-service', '--data-dir', paths.root]),
        XpExit.config,
      );
      expect(
        env.logger.errors.single,
        startsWith('This xp is not an installed bundle'),
      );
    });

    test('leaves the label to the app that registered it', () async {
      await pair();
      launchctlPrint =
          'gui/501/x = {\n\tpath = /Applications/XPath.app/x.plist\n}';

      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.failed);
      expect(env.logger.errors.single, contains('--force'));
      expect(
        await run(['install-service', '--data-dir', paths.root, '--force']),
        XpExit.ok,
      );
    });

    test('reports a bundle it cannot copy', () async {
      await pair();
      File(p.join(paths.root, 'versions')).createSync(recursive: true);

      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.failed);
      expect(env.logger.errors, isNotEmpty);
    });

    test('does not know the credentials of systemd', () async {
      await pair();

      final code = await run([
        'install-service',
        '--data-dir',
        paths.root,
        '--master-key-credential',
        '/k',
      ]);

      expect(code, 64);
    });

    test('takes only sensible options', () async {
      await pair();
      for (final arguments in [
        ['--slots', '0'],
        ['--slots', 'many'],
        ['--run-as', 'me'],
        ['--system'],
        ['extra'],
        ['--master-key-credential', 'a', '--master-key-credential-plain', 'b'],
      ]) {
        expect(
          await run([
            'install-service',
            '--data-dir',
            paths.root,
            ...arguments,
          ]),
          64,
          reason: '$arguments',
        );
      }
      expect(File(plist()).existsSync(), isFalse);
    });
  });

  group('install-service on Linux', () {
    setUp(() => use(hostOn('linux')));

    test('writes a user unit that runs current/bin/xp and is not restarted after a revoke', () async {
      await pair();

      final code = await run(['install-service', '--data-dir', paths.root]);

      expect(code, XpExit.ok, reason: env.logger.errors.join('\n'));
      final text = File(unit()).readAsStringSync();
      expect(
        text,
        contains(
          'ExecStart=${paths.currentExecutable} runner start '
          '--data-dir ${paths.root}\n',
        ),
      );
      expect(text, contains('Environment=XP_RUNNER_MANAGED=1\n'));
      expect(text, contains('RestartPreventExitStatus=77 73 78\n'));
      expect(text, contains('TimeoutStopSec=600\n'));
      expect(text, contains('WantedBy=default.target'));
      expect(text, isNot(contains('LoadCredential')));
      expect(
        calls(),
        contains('systemctl --user enable --now xp-runner.service'),
      );
    });

    test(
      'writes where the Android SDK and the JDK are when they are set',
      () async {
        use(
          hostOn(
            'linux',
            environment: {
              'ANDROID_HOME': '/opt/android-sdk',
              'JAVA_HOME': '/usr/lib/jvm/java-17-openjdk-amd64',
              'ANDROID_SDK_ROOT': '',
            },
          ),
        );
        await pair();

        expect(
          await run(['install-service', '--data-dir', paths.root]),
          XpExit.ok,
        );

        final text = File(unit()).readAsStringSync();
        expect(text, contains('Environment=ANDROID_HOME=/opt/android-sdk\n'));
        expect(
          text,
          contains(
            'Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64\n',
          ),
        );
        expect(text, isNot(contains('ANDROID_SDK_ROOT')));
      },
    );

    test('writes the omarchy-apple-dev checkout, so that ios-linux survives a '
        'restart', () async {
      use(
        hostOn(
          'linux',
          environment: {'XP_IOS_LINUX_DIR': '/home/me/omarchy-apple-dev'},
        ),
      );
      await pair();

      expect(
        await run(['install-service', '--data-dir', paths.root]),
        XpExit.ok,
      );

      expect(
        File(unit()).readAsStringSync(),
        contains('Environment=XP_IOS_LINUX_DIR=/home/me/omarchy-apple-dev\n'),
      );
    });

    test('hands the key of the credential file to the runner', () async {
      await pair();

      expect(
        await run([
          'install-service',
          '--data-dir',
          paths.root,
          '--master-key-credential',
          '/etc/xpath/key.cred',
        ]),
        XpExit.ok,
      );
      expect(
        File(unit()).readAsStringSync(),
        contains(
          'LoadCredentialEncrypted=xpath-master-key:/etc/xpath/key.cred\n',
        ),
      );

      expect(
        await run([
          'install-service',
          '--data-dir',
          paths.root,
          '--master-key-credential-plain',
          '/etc/xpath/key',
        ]),
        XpExit.ok,
      );
      expect(
        File(unit()).readAsStringSync(),
        contains('LoadCredential=xpath-master-key:/etc/xpath/key\n'),
      );
    });

    test('a system unit needs a user to run as', () async {
      await pair();

      expect(
        await run(['install-service', '--data-dir', paths.root, '--system']),
        64,
      );
      expect(env.logger.errors, isEmpty);
    });
  });

  group('uninstall-service', () {
    test('removes the service', () async {
      await pair();
      await run(['install-service', '--data-dir', paths.root]);

      final code = await run(['uninstall-service', '--data-dir', paths.root]);

      expect(code, XpExit.ok);
      expect(File(plist()).existsSync(), isFalse);
      expect(
        env.logger.infos.last,
        contains('Stopped and removed the runner service'),
      );
      expect(
        calls(),
        contains('launchctl bootout gui/501/ly.abdurahman.xpath.runner'),
      );
    });

    test('says so when there is none', () async {
      expect(await run(['uninstall-service']), XpExit.ok);
      expect(env.logger.infos.last, 'There is no runner service to remove.');
    });

    test('reports a system without a service manager', () async {
      use(hostOn('windows'));

      expect(await run(['uninstall-service']), XpExit.failed);
      expect(env.logger.errors.single, contains('windows'));
    });
  });

  group('service-status', () {
    test('shows a running service and exits 0, anything else 1', () async {
      await pair();
      await run(['install-service', '--data-dir', paths.root]);
      launchctlPrint = 'gui/501/x = {\n\tstate = running\n\tpid = 4242\n}';

      expect(
        await run(['service-status', '--data-dir', paths.root]),
        XpExit.ok,
      );
      final out = env.logger.out;
      expect(out, contains('ly.abdurahman.xpath.runner): running'));
      expect(out, contains('pid:    4242'));
      expect(out, contains('state:  running'));

      launchctlPrint = null;
      expect(
        await run(['service-status', '--data-dir', paths.root]),
        XpExit.failed,
      );
      expect(env.logger.infos.last, contains('state:  not loaded'));
      expect(env.logger.out, contains('installed, not loaded'));

      launchctlPrint = 'gui/501/x = {\n\tstate = waiting\n}';
      await run(['service-status', '--data-dir', paths.root]);
      expect(env.logger.out, contains('installed, not running'));
    });

    test('knows a service that is not installed', () async {
      expect(
        await run(['service-status', '--data-dir', paths.root]),
        XpExit.failed,
      );
      expect(env.logger.out, contains('not installed'));
    });

    test('reads a systemd unit', () async {
      use(hostOn('linux'));

      expect(await run(['service-status']), XpExit.ok);
      expect(env.logger.out, contains('active (running), enabled'));
    });
  });

  group('the unit file that ships', () {
    test('is what the template renders for the reference definition', () {
      final shipped = File('../../tool/release/linux/xp-runner.service');

      expect(
        shipped.existsSync(),
        isTrue,
        reason: 'tool/release/linux/xp-runner.service is missing',
      );
      expect(
        shipped.readAsStringSync(),
        renderSystemdUnit(
          RunnerServiceDefinition.reference,
          scope: ServiceScope.user,
        ),
        reason:
            'tool/release/linux/xp-runner.service is generated from '
            'RunnerServiceDefinition.reference: write '
            'renderSystemdUnit(RunnerServiceDefinition.reference, '
            'scope: ServiceScope.user) to it.',
      );
    });
  });
}
