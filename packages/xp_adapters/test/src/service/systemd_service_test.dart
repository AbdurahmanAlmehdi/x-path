import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

void main() {
  late Directory units;
  late FakeProcessRunner runner;
  late ServiceDefinition definition;
  var lingering = 'Linger=no\n';
  var failing = <String>{};
  var shown =
      'LoadState=loaded\nActiveState=active\nSubState=running\n'
      'MainPID=321\nUnitFileState=enabled\n';

  SystemdService service({ServiceScope scope = ServiceScope.user}) =>
      SystemdService(
        runner: runner,
        home: '/home/me',
        user: 'me',
        scope: scope,
        unitDirectory: units.path,
      );

  List<String> calls() => [
    for (final call in runner.calls)
      [call.executable, ...call.arguments].join(' '),
  ];

  setUp(() {
    units = tempDirectory();
    lingering = 'Linger=no\n';
    failing = {};
    shown =
        'LoadState=loaded\nActiveState=active\nSubState=running\n'
        'MainPID=321\nUnitFileState=enabled\n';
    runner = FakeProcessRunner((call) {
      final verb = call.executable == 'loginctl'
          ? 'loginctl'
          : call.arguments.firstWhere((a) => !a.startsWith('--'));
      if (failing.contains(verb)) {
        return const ProcessOutput(
          exitCode: 1,
          stderr: 'Failed to connect to bus\n',
        );
      }
      if (verb == 'loginctl') {
        return ProcessOutput(exitCode: 0, stdout: lingering);
      }
      if (verb == 'show') return ProcessOutput(exitCode: 0, stdout: shown);
      return const ProcessOutput(exitCode: 0);
    });
    definition = const ServiceDefinition(
      label: 'ly.abdurahman.xpath.xpd',
      unitName: 'xpd',
      description: 'XPath engine',
      executable: '/opt/100%/xpd',
      arguments: ['serve'],
      path: '/usr/bin',
      logName: 'xpd',
    );
  });

  String unit() => p.join(units.path, 'xpd.service');

  group('install', () {
    test('writes the unit with its text escaped, then enables it', () async {
      final installed = await service().install(definition);

      expect(installed.path, unit());
      expect(
        File(unit()).readAsStringSync(),
        renderSystemdUnit(
          definition.escapedForSystemd(),
          scope: ServiceScope.user,
        ),
      );
      expect(File(unit()).readAsStringSync(), contains('/opt/100%%/xpd'));
      expect(calls(), [
        'systemctl --user daemon-reload',
        'systemctl --user enable --now xpd.service',
        'loginctl show-user me --property=Linger',
      ]);
      expect(File('${unit()}.partial').existsSync(), isFalse);
    });

    test('hints at linger for a user who does not have it', () async {
      final installed = await service().install(definition);

      expect(installed.notes.single, contains('enable-linger me'));
    });

    test('says nothing about linger when the user has it', () async {
      lingering = 'Linger=yes\n';

      expect((await service().install(definition)).notes, isEmpty);
    });

    test('hints at linger when loginctl cannot say', () async {
      runner = FakeProcessRunner((call) {
        if (call.executable == 'loginctl') {
          throw const ProcessStartException('loginctl', 'missing');
        }
        return const ProcessOutput(exitCode: 0);
      });

      expect((await service().install(definition)).notes, hasLength(1));
    });

    test('a system unit has no --user and needs no linger', () async {
      final installed = await service(scope: ServiceScope.system)
          .install(definition);

      expect(calls(), [
        'systemctl daemon-reload',
        'systemctl enable --now xpd.service',
      ]);
      expect(installed.notes, isEmpty);
    });

    test(
      "fails with systemctl's message and the way to a user session",
      () async {
        failing = {'enable'};

        await expectLater(
          service().install(definition),
          throwsA(
            isA<ServiceException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('enable failed (exit 1)'),
                contains('Failed to connect to bus'),
                contains('user session'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'a system unit that fails does not mention the user session',
      () async {
        failing = {'daemon-reload'};

        await expectLater(
          service(scope: ServiceScope.system).install(definition),
          throwsA(
            isA<ServiceException>().having(
              (error) => error.message,
              'message',
              isNot(contains('user session')),
            ),
          ),
        );
      },
    );

    test('a failure without a message still says what failed', () async {
      runner = FakeProcessRunner((call) => const ProcessOutput(exitCode: 3));

      await expectLater(
        service().install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            contains('no message'),
          ),
        ),
      );
    });

    test('asks for root when it cannot write a system unit', () async {
      final blocked = File(p.join(units.path, 'file'))..writeAsStringSync('x');
      final manager = SystemdService(
        runner: runner,
        home: '/home/me',
        user: 'me',
        scope: ServiceScope.system,
        unitDirectory: p.join(blocked.path, 'sub'),
      );

      await expectLater(
        manager.install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Cannot write'), contains('sudo')),
          ),
        ),
      );
    });

    test(
      'cannot write a user unit either, and does not ask for root',
      () async {
        final blocked = File(p.join(units.path, 'file'))
          ..writeAsStringSync('x');
        final manager = SystemdService(
          runner: runner,
          home: '/home/me',
          user: 'me',
          unitDirectory: p.join(blocked.path, 'sub'),
        );

        await expectLater(
          manager.install(definition),
          throwsA(
            isA<ServiceException>().having(
              (error) => error.message,
              'message',
              isNot(contains('sudo')),
            ),
          ),
        );
      },
    );

    test('says so when systemctl does not exist', () async {
      runner.startError = const ProcessStartException('systemctl', 'missing');

      await expectLater(
        service().install(definition),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            contains('Cannot run systemctl'),
          ),
        ),
      );
    });

    test('defaults to the user unit folder of the home directory', () {
      expect(
        SystemdService(
          runner: runner,
          home: '/home/me',
          user: 'me',
        ).unitDirectory,
        '/home/me/.config/systemd/user',
      );
      expect(
        SystemdService(
          runner: runner,
          home: '/home/me',
          user: 'me',
          scope: ServiceScope.system,
        ).unitDirectory,
        '/etc/systemd/system',
      );
    });
  });

  group('uninstall', () {
    test('disables the unit, deletes it and reloads', () async {
      await service().install(definition);
      runner.calls.clear();

      expect(await service().uninstall(definition), isTrue);

      expect(File(unit()).existsSync(), isFalse);
      expect(calls(), [
        'systemctl --user disable --now xpd.service',
        'systemctl --user daemon-reload',
      ]);
    });

    test('goes on when the unit was not enabled', () async {
      await service().install(definition);
      failing = {'disable'};

      expect(await service().uninstall(definition), isTrue);
    });

    test('is fine with a unit that was never installed', () async {
      expect(await service().uninstall(definition), isFalse);
    });
  });

  group('status', () {
    test('reads the state of a running unit', () async {
      await service().install(definition);

      final status = await service().status(definition);

      expect(status.installed, isTrue);
      expect(status.loaded, isTrue);
      expect(status.running, isTrue);
      expect(status.pid, 321);
      expect(status.detail, 'active (running), enabled');
      expect(status.path, unit());
    });

    test('a unit that is not there is unknown to systemd', () async {
      shown =
          'LoadState=not-found\nActiveState=inactive\nSubState=dead\n'
          'MainPID=0\n';

      final status = await service().status(definition);

      expect(status.installed, isFalse);
      expect(status.loaded, isFalse);
      expect(status.running, isFalse);
      expect(status.pid, isNull);
      expect(status.detail, 'inactive (dead), not enabled');
    });

    test('a failing systemctl is unknown to systemd', () async {
      failing = {'show'};

      final status = await service().status(definition);

      expect(status.detail, 'unknown to systemd');
      expect(status.running, isFalse);
    });
  });

  group('ServiceManager.forPlatform', () {
    test('is launchd on macOS and systemd on Linux', () {
      expect(
        ServiceManager.forPlatform(
          operatingSystem: 'macos',
          runner: runner,
          home: '/Users/me',
          user: 'me',
        ),
        isA<LaunchdService>(),
      );
      expect(
        ServiceManager.forPlatform(
          operatingSystem: 'linux',
          runner: runner,
          home: '/home/me',
          user: 'me',
          scope: ServiceScope.system,
        ),
        isA<SystemdService>(),
      );
    });

    test('has no system scope on macOS and no other system', () {
      expect(
        () => ServiceManager.forPlatform(
          operatingSystem: 'macos',
          runner: runner,
          home: '/Users/me',
          user: 'me',
          scope: ServiceScope.system,
        ),
        throwsA(
          isA<ServiceException>().having(
            (error) => error.message,
            'message',
            contains('--system is for Linux'),
          ),
        ),
      );
      expect(
        () => ServiceManager.forPlatform(
          operatingSystem: 'windows',
          runner: runner,
          home: r'C:\Users\me',
          user: 'me',
        ),
        throwsA(
          isA<ServiceException>().having(
            (error) => '${error.message} $error',
            'message',
            allOf(contains('windows'), contains('ServiceException')),
          ),
        ),
      );
    });
  });
}
