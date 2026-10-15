import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';

void main() {
  late Directory root;
  late String home;
  late WatchedSink out;
  late WatchedSink err;
  late FakeProcessRunner processes;
  // What `launchctl print` / `systemctl show` answer.
  String? launchctlPrint;
  var systemctlShow =
      'LoadState=loaded\nActiveState=active\nSubState=running\n'
      'MainPID=77\nUnitFileState=enabled\n';

  Future<int> run(
    List<String> args, {
    String operatingSystem = 'macos',
    String executable = '/opt/xpath/xpd/bin/xpd',
    Map<String, String> environment = const {},
    Directory? systemUnits,
  }) async {
    final context = XpdContext(
      out: out,
      err: err,
      shutdown: const Stream.empty(),
      environment: {'HOME': home, 'USER': 'me', ...environment},
      operatingSystem: operatingSystem,
      processes: processes,
      executable: executable,
      serviceManager: systemUnits == null
          ? null
          : (scope) => SystemdService(
              runner: processes,
              home: home,
              user: 'me',
              scope: scope,
              unitDirectory: systemUnits.path,
            ),
    );
    final runner = CommandRunner<int>('xpd', 'test')
      ..addCommand(InstallServiceCommand(context))
      ..addCommand(UninstallServiceCommand(context))
      ..addCommand(ServiceStatusCommand(context));
    try {
      return await runner.run(args) ?? 0;
    } on UsageException catch (error) {
      err.writeln(error.message);
      return 64;
    }
  }

  List<String> calls() => [
    for (final call in processes.calls)
      [call.executable, ...call.arguments].join(' '),
  ];

  String plist() =>
      p.join(home, 'Library', 'LaunchAgents', 'ly.abdurahman.xpath.xpd.plist');

  setUp(() {
    root = Directory.systemTemp.createTempSync('xpd_service_');
    home = p.join(root.path, 'home');
    out = WatchedSink();
    err = WatchedSink();
    launchctlPrint = null;
    systemctlShow =
        'LoadState=loaded\nActiveState=active\nSubState=running\n'
        'MainPID=77\nUnitFileState=enabled\n';
    processes = FakeProcessRunner((call) {
      if (call.executable == 'id') {
        return const ProcessOutput(exitCode: 0, stdout: '501\n');
      }
      if (call.executable == 'launchctl' && call.arguments.first == 'print') {
        return launchctlPrint == null
            ? const ProcessOutput(exitCode: 113)
            : ProcessOutput(exitCode: 0, stdout: launchctlPrint!);
      }
      if (call.executable == 'systemctl' && call.arguments.contains('show')) {
        return ProcessOutput(exitCode: 0, stdout: systemctlShow);
      }
      if (call.executable == 'loginctl') {
        return const ProcessOutput(exitCode: 0, stdout: 'Linger=yes\n');
      }
      return const ProcessOutput(exitCode: 0);
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('install-service on macOS', () {
    test('writes the LaunchAgent of the running xpd and loads it', () async {
      final code = await run(['install-service', '--data-dir', '$home/data']);

      expect(code, 0, reason: '$err');
      final text = File(plist()).readAsStringSync();
      expect(text, contains('<string>ly.abdurahman.xpath.xpd</string>'));
      expect(text, contains('<string>/opt/xpath/xpd/bin/xpd</string>'));
      expect(text, contains('<string>serve</string>'));
      expect(text, contains('<string>$home/data</string>'));
      expect(text, contains('/opt/homebrew/bin'));
      expect(text, contains('$home/data/service-logs/xpd.out.log'));
      expect(Directory('$home/data/service-logs').existsSync(), isTrue);
      expect(calls(), contains('launchctl bootstrap gui/501 ${plist()}'));
      expect('$out', contains('Installed the xpd service'));
      expect('$out', contains('xpd service-status'));
    });

    test('passes the serve options and a PATH of its own on', () async {
      final code = await run([
        'install-service',
        '--data-dir',
        '$home/data',
        '--host',
        '0.0.0.0',
        '--port',
        '9000',
        '--slots',
        '3',
        '--path',
        '/a:/b',
        '--executable',
        '/usr/local/lib/xpath/bin/xpd',
      ]);

      expect(code, 0, reason: '$err');
      final text = File(plist()).readAsStringSync();
      for (final value in ['--host', '0.0.0.0', '--port', '9000', '--slots']) {
        expect(text, contains('<string>$value</string>'));
      }
      expect(text, contains('<string>/a:/b</string>'));
      expect(text, contains('/usr/local/lib/xpath/bin/xpd'));
    });

    test('uses the data directory the default way', () async {
      final code = await run(['install-service']);

      expect(code, 0, reason: '$err');
      expect(
        File(plist()).readAsStringSync(),
        contains('<string>$home/Library/Application Support/XPath</string>'),
      );
    });

    test('leaves the label to the app that registered it', () async {
      launchctlPrint =
          'gui/501/x = {\n\tpath = /Applications/XPath.app/x.plist\n}';

      final code = await run(['install-service']);

      expect(code, 1);
      expect('$err', contains('--force'));
      expect(File(plist()).existsSync(), isFalse);

      expect(await run(['install-service', '--force']), 0);
      expect(File(plist()).existsSync(), isTrue);
    });

    test('does not know the master key credentials of systemd', () async {
      final code = await run([
        'install-service',
        '--master-key-credential',
        '/k',
      ]);

      expect(code, 64);
      expect('$err', contains('Keychain'));
    });

    test('reports a launchctl that fails', () async {
      processes = FakeProcessRunner(
        (call) => call.executable == 'id'
            ? const ProcessOutput(exitCode: 0, stdout: '501\n')
            : ProcessOutput(
                exitCode: call.arguments.first == 'print' ? 1 : 5,
                stderr: 'boom',
              ),
      );

      final code = await run(['install-service']);

      expect(code, 1);
      expect('$err', allOf(startsWith('xpd: '), contains('boom')));
    });
  });

  group('install-service executable', () {
    test('is not a dart run', () async {
      final code = await run(['install-service'], executable: '/sdk/bin/dart');

      expect(code, 64);
      expect('$err', contains('is not an installed xpd'));
      expect(processes.calls, isEmpty);
    });

    test('has to be known', () async {
      final code = await run(['install-service'], executable: '');

      expect(code, 64);
      expect('$err', contains('give --executable'));
    });

    test('is an absolute path when given', () async {
      final code = await run(['install-service', '--executable', 'xpd']);

      expect(code, 64);
      expect('$err', contains('absolute'));
    });
  });

  group('install-service on Linux', () {
    late Directory units;

    setUp(() => units = Directory(p.join(root.path, 'units')));

    Future<int> linux(List<String> args) => run(
      ['install-service', ...args],
      operatingSystem: 'linux',
      systemUnits: units,
    );

    String unit() => File(p.join(units.path, 'xpd.service')).readAsStringSync();

    test('writes a user unit and enables it', () async {
      final code = await linux(['--data-dir', '$home/data']);

      expect(code, 0, reason: '$err');
      expect(unit(), contains('ExecStart=/opt/xpath/xpd/bin/xpd serve '));
      expect(unit(), contains('WantedBy=default.target'));
      expect(unit(), isNot(contains('LoadCredential')));
      expect(calls(), contains('systemctl --user enable --now xpd.service'));
    });

    test('hands the master key to the engine as a credential', () async {
      expect(
        await linux(['--master-key-credential', '$home/key.cred']),
        0,
        reason: '$err',
      );
      expect(
        unit(),
        contains('LoadCredentialEncrypted=xpath-master-key:$home/key.cred\n'),
      );

      expect(
        await linux(['--master-key-credential-plain', '$home/key']),
        0,
        reason: '$err',
      );
      expect(unit(), contains('LoadCredential=xpath-master-key:$home/key\n'));
    });

    test('takes one kind of credential, not both', () async {
      final code = await linux([
        '--master-key-credential',
        'a',
        '--master-key-credential-plain',
        'b',
      ]);

      expect(code, 64);
      expect('$err', contains('not both'));
    });

    test('a system unit needs a user to run as', () async {
      expect(await linux(['--system']), 64);
      expect('$err', contains('--run-as'));

      expect(await linux(['--run-as', 'xpath']), 64);

      expect(await linux(['--system', '--run-as', 'xpath']), 0, reason: '$err');
      expect(unit(), contains('User=xpath\n'));
      expect(unit(), contains('WantedBy=multi-user.target'));
      expect(calls(), contains('systemctl enable --now xpd.service'));
    });
  });

  group('uninstall-service', () {
    test('removes the LaunchAgent', () async {
      await run(['install-service']);
      out = WatchedSink();

      final code = await run(['uninstall-service']);

      expect(code, 0);
      expect(File(plist()).existsSync(), isFalse);
      expect('$out', contains('Stopped and removed'));
      expect('$out', contains('untouched'));
    });

    test('says so when there is nothing to remove', () async {
      expect(await run(['uninstall-service']), 0);
      expect('$out', contains('There is no xpd service to remove.'));
    });

    test('reports a platform without a service manager', () async {
      final code = await run(['uninstall-service'], operatingSystem: 'windows');

      expect(code, 1);
      expect('$err', contains('windows'));
    });
  });

  group('service-status', () {
    test('shows a running service and exits 0', () async {
      await run(['install-service']);
      launchctlPrint = 'gui/501/x = {\n\tstate = running\n\tpid = 4242\n}';
      out = WatchedSink();

      final code = await run(['service-status']);

      expect(code, 0);
      expect('$out', contains('ly.abdurahman.xpath.xpd): running'));
      expect('$out', contains(plist()));
      expect('$out', contains('pid:    4242'));
      expect('$out', contains('state:  running'));
    });

    test('tells installed, loaded and missing apart, and exits 1', () async {
      expect(await run(['service-status']), 1);
      expect('$out', contains('not installed'));

      await run(['install-service']);
      out = WatchedSink();
      expect(await run(['service-status']), 1);
      expect('$out', contains('installed, not loaded'));

      launchctlPrint = 'gui/501/x = {\n\tstate = waiting\n}';
      out = WatchedSink();
      expect(await run(['service-status']), 1);
      expect('$out', contains('installed, not running'));
      expect('$out', isNot(contains('pid:')));
    });

    test('reads a systemd unit', () async {
      final units = Directory(p.join(root.path, 'units'));

      final code = await run(
        ['service-status'],
        operatingSystem: 'linux',
        systemUnits: units,
      );

      expect(code, 0);
      expect('$out', contains('running'));
      expect('$out', contains('active (running), enabled'));
    });
  });

  group('the unit file that ships', () {
    test('is what the template renders for the reference definition', () {
      final shipped = File('../../tool/release/linux/xpd.service');

      expect(
        shipped.existsSync(),
        isTrue,
        reason: 'tool/release/linux/xpd.service is missing',
      );
      expect(
        shipped.readAsStringSync(),
        renderSystemdUnit(XpdService.reference, scope: ServiceScope.user),
        reason:
            'tool/release/linux/xpd.service is generated from '
            'XpdService.reference: write '
            'renderSystemdUnit(XpdService.reference, scope: ServiceScope.user) '
            'to it.',
      );
    });
  });

  test('runXpd has the three commands', () async {
    final code = await runXpd(
      ['service-status'],
      out: out,
      err: err,
      shutdown: const Stream<void>.empty(),
      environment: {'HOME': home},
      operatingSystem: 'macos',
      processes: processes,
      executable: '/opt/xpath/xpd/bin/xpd',
    );

    expect(code, 1);
    expect('$out', contains('not installed'));
  });
}
