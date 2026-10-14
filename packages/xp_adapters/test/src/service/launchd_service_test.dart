import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

void main() {
  late Directory home;
  late FakeProcessRunner launchctl;
  late LaunchdService service;
  late ServiceDefinition definition;
  // What `launchctl print` answers, or null for "not loaded".
  String? loaded;
  var bootstrapExit = 0;

  List<List<String>> calls() => [
    for (final call in launchctl.calls) [call.executable, ...call.arguments],
  ];

  setUp(() {
    home = tempDirectory();
    loaded = null;
    bootstrapExit = 0;
    launchctl = FakeProcessRunner((call) {
      if (call.executable == 'id') {
        return const ProcessOutput(exitCode: 0, stdout: '501\n');
      }
      switch (call.arguments.first) {
        case 'print':
          return loaded == null
              ? const ProcessOutput(exitCode: 113, stderr: 'not found')
              : ProcessOutput(exitCode: 0, stdout: loaded!);
        case 'bootstrap':
          return ProcessOutput(
            exitCode: bootstrapExit,
            stderr: bootstrapExit == 0 ? '' : 'Bootstrap failed: 5\n',
          );
        default:
          return const ProcessOutput(exitCode: 0);
      }
    });
    service = LaunchdService(runner: launchctl, home: home.path);
    definition = ServiceDefinition(
      label: 'ly.abdurahman.xpath.xpd',
      unitName: 'xpd',
      description: 'XPath engine',
      executable: '/opt/xpath/bin/xpd',
      arguments: const ['serve'],
      path: '/usr/bin',
      logName: 'xpd',
      logDirectory: p.join(home.path, 'logs'),
    );
  });

  String plist() => p.join(
    home.path,
    'Library',
    'LaunchAgents',
    'ly.abdurahman.xpath.xpd.plist',
  );

  group('install', () {
    test('writes the property list and bootstraps it into gui/<uid>', () async {
      final installed = await service.install(definition);

      expect(installed.path, plist());
      expect(
        File(plist()).readAsStringSync(),
        renderLaunchAgentPlist(definition),
      );
      expect(Directory(p.join(home.path, 'logs')).existsSync(), isTrue);
      expect(calls(), [
        ['id', '-u'],
        ['launchctl', 'print', 'gui/501/ly.abdurahman.xpath.xpd'],
        ['launchctl', 'bootstrap', 'gui/501', plist()],
      ]);
      expect(installed.notes.single, contains('xpd.out.log'));
      expect(File('${plist()}.partial').existsSync(), isFalse);
    });

    test('replaces its own earlier registration', () async {
      loaded =
          '''
gui/501/ly.abdurahman.xpath.xpd = {
\tpath = ${plist()}
\tstate = running
}''';

      await service.install(definition);

      expect(calls().map((call) => call[1]), [
        '-u',
        'print',
        'bootout',
        'bootstrap',
      ]);
    });

    test('refuses a label that something else registered', () async {
      loaded = '''
gui/501/ly.abdurahman.xpath.xpd = {
\tpath = /Applications/XPath.app/Contents/Library/LaunchAgents/x.plist
\tstate = running
}''';

      await expectLater(
        service.install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            allOf(contains('XPath app'), contains('--force')),
          ),
        ),
      );
      expect(File(plist()).existsSync(), isFalse);
      expect(calls().map((call) => call[1]), isNot(contains('bootstrap')));
    });

    test('--force takes the label over', () async {
      loaded = '''
gui/501/ly.abdurahman.xpath.xpd = {
\tpath = /Applications/XPath.app/x.plist
}''';

      await service.install(definition, force: true);

      expect(calls().map((call) => call[1]), contains('bootout'));
      expect(File(plist()).existsSync(), isTrue);
    });

    test('takes a loaded service that names no path as its own', () async {
      loaded = 'gui/501/ly.abdurahman.xpath.xpd = {\n\tstate = waiting\n}';

      await service.install(definition);

      expect(File(plist()).existsSync(), isTrue);
    });

    test('says how to get a login session when bootstrap fails', () async {
      bootstrapExit = 5;

      await expectLater(
        service.install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('exit 5'),
              contains('Bootstrap failed: 5'),
              contains('gui/501'),
              contains('log in'),
            ),
          ),
        ),
      );
    });

    test('with no log folder tells nothing about logs', () async {
      final installed = await service.install(
        ServiceDefinition(
          label: definition.label,
          unitName: 'xpd',
          description: 'd',
          executable: '/x',
          arguments: const [],
          path: '/usr/bin',
          logName: 'xpd',
        ),
      );

      expect(installed.notes, isEmpty);
    });

    test('says so when launchctl does not exist', () async {
      service = LaunchdService(
        runner: launchctl,
        home: home.path,
        uid: () async => '501',
      );
      launchctl.startError = const ProcessStartException(
        'launchctl',
        'No such file',
      );

      await expectLater(
        service.install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            contains('Cannot run launchctl'),
          ),
        ),
      );
    });

    test('with no message from launchctl still says what failed', () async {
      launchctl = FakeProcessRunner((call) {
        if (call.executable == 'id') {
          return const ProcessOutput(exitCode: 0, stdout: '501\n');
        }
        return ProcessOutput(exitCode: call.arguments.first == 'print' ? 1 : 9);
      });
      service = LaunchdService(runner: launchctl, home: home.path);

      await expectLater(
        service.install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            contains('no message'),
          ),
        ),
      );
    });
  });

  group('uninstall', () {
    test('boots the service out and deletes the property list', () async {
      await service.install(definition);
      launchctl.calls.clear();

      expect(await service.uninstall(definition), isTrue);

      expect(File(plist()).existsSync(), isFalse);
      expect(calls(), [
        ['id', '-u'],
        ['launchctl', 'bootout', 'gui/501/ly.abdurahman.xpath.xpd'],
      ]);
    });

    test('is fine with a service that was never installed', () async {
      expect(await service.uninstall(definition), isFalse);
    });
  });

  group('status', () {
    test('reads the state, the process and the last exit code', () async {
      await service.install(definition);
      loaded =
          '''
gui/501/ly.abdurahman.xpath.xpd = {
\tactive count = 1
\tpath = ${plist()}
\tstate = running
\tpid = 4242
\tlast exit code = (never exited)
}''';

      final status = await service.status(definition);

      expect(status.installed, isTrue);
      expect(status.loaded, isTrue);
      expect(status.running, isTrue);
      expect(status.pid, 4242);
      expect(status.path, plist());
      expect(status.detail, 'running, last exit code (never exited)');
    });

    test('a loaded service that waits does not run', () async {
      loaded = 'gui/501/x = {\n\tstate = waiting\n}';

      final status = await service.status(definition);

      expect(status.running, isFalse);
      expect(status.loaded, isTrue);
      expect(status.pid, isNull);
      expect(status.detail, 'waiting');
    });

    test('tells installed from loaded', () async {
      var status = await service.status(definition);
      expect(status.detail, 'not installed');
      expect(status.installed, isFalse);
      expect(status.loaded, isFalse);

      await service.install(definition);
      status = await service.status(definition);
      expect(status.detail, 'not loaded');
      expect(status.installed, isTrue);
    });
  });

  test('takes the user id from a function when it is given one', () async {
    service = LaunchdService(
      runner: launchctl,
      home: home.path,
      launchAgents: p.join(home.path, 'agents'),
      uid: () async => '777',
    );

    await service.install(definition);

    expect(calls().first, [
      'launchctl',
      'print',
      'gui/777/${definition.label}',
    ]);
    expect(
      File(p.join(home.path, 'agents', '${definition.label}.plist'))
          .existsSync(),
      isTrue,
    );
  });

  test('says so when id does not exist', () async {
    launchctl.startError = const ProcessStartException('id', 'missing');

    await expectLater(
      service.status(definition),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.message,
          'message',
          contains('Cannot run id'),
        ),
      ),
    );
  });

  test('cannot tell the user id when id fails', () async {
    launchctl = FakeProcessRunner(
      (call) => const ProcessOutput(exitCode: 1, stdout: 'nope'),
    );
    service = LaunchdService(runner: launchctl, home: home.path);

    await expectLater(
      service.status(definition),
      throwsA(isA<ServiceException>()),
    );
  });
}
