import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/fake_flutter_installer.dart';
import 'fixtures.dart';

const _fvmSdk = ResolvedFlutter(
  path: '/Users/dev/fvm/versions/3.47.6',
  version: '3.47.6',
  dartVersion: '3.13.5',
  source: FlutterSource.fvm,
);

const _cacheMachine =
    '{"frameworkVersion": "3.47.6", "dartSdkVersion": "3.13.5"}';

/// A machine for the resolver: what `fvm api list` prints (`null`: no fvm),
/// what `fvm install` does and what the cached SDK reports.
class _Machine {
  new({
    this.fvmList,
    this.installedByFvm,
    this.installExitCode = 0,
    this.flutterOutput = const ProcessOutput(
      exitCode: 0,
      stdout: _cacheMachine,
    ),
  });

  String? fvmList;
  String? installedByFvm;
  int installExitCode;
  ProcessOutput flutterOutput;

  late final runner = FakeProcessRunner((call) {
    final arguments = call.arguments.join(' ');
    if (call.executable == 'fvm') {
      final list = fvmList;
      if (list == null) {
        throw const ProcessStartException('fvm', 'not found');
      }
      if (arguments == 'api list') {
        return ProcessOutput(exitCode: 0, stdout: list);
      }
      if (arguments.startsWith('install ')) {
        if (installExitCode == 0) fvmList = installedByFvm ?? list;
        return ProcessOutput(exitCode: installExitCode, stderr: 'no');
      }
    }
    if (call.executable.endsWith('/bin/flutter')) return flutterOutput;
    throw StateError('unexpected ${call.executable} $arguments');
  });

  List<String> get commands => [
    for (final call in runner.calls)
      '${call.executable} ${call.arguments.join(' ')}',
  ];
}

void main() {
  late FakeFlutterInstaller installer;

  FlutterResolver resolver(_Machine machine) => FlutterResolver(
    runner: machine.runner,
    installer: installer,
    commandTimeout: const Duration(seconds: 1),
    fvmInstallTimeout: const Duration(seconds: 1),
  );

  setUp(() => installer = FakeFlutterInstaller());

  group('with fvm', () {
    test('uses the SDK fvm has cached', () async {
      final machine = _Machine(fvmList: fixture('fvm_3.2.1_api_list.json'));

      final flutter = await resolver(machine).resolve('3.47.6');

      expect(flutter, _fvmSdk);
      expect(
        flutter.flutterExecutable,
        '/Users/dev/fvm/versions/3.47.6/bin/flutter',
      );
      expect(machine.commands, ['fvm api list']);
      expect(installer.installs, isEmpty);
    });

    test('reads the list of fvm 4 as well', () async {
      final machine = _Machine(fvmList: fixture('fvm_4.0.5_api_list.json'));

      expect(await resolver(machine).resolve('3.47.4'), isNotNull);
    });

    test('installs a version fvm does not have, then uses it', () async {
      final machine = _Machine(
        fvmList: fixture('fvm_3.2.1_api_list.json'),
        installedByFvm: fixture('fvm_3.2.1_api_list.json')
            .replaceAll('3.47.4', '3.50.0'),
      );

      final flutter = await resolver(machine).resolve('3.50.0');

      expect(flutter.source, FlutterSource.fvm);
      expect(flutter.path, '/Users/dev/fvm/versions/3.50.0');
      expect(machine.commands, [
        'fvm api list',
        'fvm install 3.50.0',
        'fvm api list',
      ]);
      expect(installer.installs, isEmpty);
    });

    test('takes the Flutter version of a channel from fvm', () async {
      final machine = _Machine(
        fvmList:
            '{"versions": [{"name": "stable", "directory": "/f/stable", '
            '"flutterSdkVersion": "3.47.6"}]}',
      );

      final flutter = await resolver(machine).resolve('stable');

      expect(flutter.version, '3.47.6');
      expect(flutter.dartVersion, isNull);
    });

    test('falls back to the version asked for when fvm names none', () async {
      final machine = _Machine(
        fvmList: '{"versions": [{"name": "3.47.6", "directory": "/f"}]}',
      );

      expect((await resolver(machine).resolve('3.47.6')).version, '3.47.6');
    });

    test('falls back to the cache when fvm cannot install it', () async {
      final machine = _Machine(
        fvmList: fixture('fvm_3.2.1_api_list.json'),
        installExitCode: 1,
        flutterOutput: const ProcessOutput(
          exitCode: 0,
          stdout: '{"frameworkVersion": "3.47.5"}',
        ),
      );

      final flutter = await resolver(machine).resolve('3.47.5');

      expect(flutter.source, FlutterSource.cache);
      expect(installer.installs, ['3.47.5']);
    });

    test(
      'falls back to the cache when fvm installs but does not list it',
      () async {
        final machine = _Machine(fvmList: fixture('fvm_3.2.1_api_list.json'));
        installer.installed.add('3.47.5');
        machine.flutterOutput = const ProcessOutput(
          exitCode: 0,
          stdout: '{"frameworkVersion": "3.47.5"}',
        );

        final flutter = await resolver(machine).resolve('3.47.5');

        expect(flutter.source, FlutterSource.cache);
        expect(machine.commands.take(3), [
          'fvm api list',
          'fvm install 3.47.5',
          'fvm api list',
        ]);
      },
    );

    test('falls back to the cache when fvm install is too slow', () async {
      final runner = FakeProcessRunner((call) {
        if (call.arguments.first == 'api') {
          return const ProcessOutput(exitCode: 0, stdout: '{"versions": []}');
        }
        if (call.executable == 'fvm') return Completer<ProcessOutput>().future;
        return const ProcessOutput(exitCode: 0, stdout: _cacheMachine);
      });
      installer.installed.add('3.47.6');

      final flutter = await FlutterResolver(
        runner: runner,
        installer: installer,
        fvmInstallTimeout: const Duration(milliseconds: 10),
      ).resolve('3.47.6');

      expect(flutter.source, FlutterSource.cache);
      expect(
        runner.calls.firstWhere((c) => c.arguments.first == 'install').killed,
        isTrue,
      );
    });

    test('treats an fvm that fails or prints nonsense as absent', () async {
      for (final output in [
        const ProcessOutput(exitCode: 1, stderr: 'fvm: error'),
        const ProcessOutput(exitCode: 0, stdout: 'not json'),
      ]) {
        installer.installed.add('3.47.6');
        final runner = FakeProcessRunner(
          (call) => call.executable == 'fvm'
              ? output
              : const ProcessOutput(exitCode: 0, stdout: _cacheMachine),
        );

        final flutter = await FlutterResolver(
          runner: runner,
          installer: installer,
        ).resolve('3.47.6');

        expect(flutter.source, FlutterSource.cache);
        expect(
          runner.calls.map((c) => c.arguments.first),
          isNot(contains('install')),
        );
      }
    });

    test('uses the fvm it was given', () async {
      final runner = FakeProcessRunner(
        (_) => ProcessOutput(
          exitCode: 0,
          stdout: fixture('fvm_3.2.1_api_list.json'),
        ),
      );

      await FlutterResolver(
        runner: runner,
        installer: installer,
        fvmExecutable: '/opt/homebrew/bin/fvm',
      ).resolve('3.47.6');

      expect(runner.calls.single.executable, '/opt/homebrew/bin/fvm');
    });
  });

  group('without fvm', () {
    test('uses the SDK in the cache (hit), without installing', () async {
      installer.installed.add('3.47.6');
      final machine = _Machine();

      final flutter = await resolver(machine).resolve('3.47.6');

      expect(
        flutter,
        const ResolvedFlutter(
          path: '/data/toolchains/flutter/3.47.6',
          version: '3.47.6',
          dartVersion: '3.13.5',
          source: FlutterSource.cache,
        ),
      );
      expect(installer.installs, isEmpty);
      expect(machine.commands, [
        'fvm api list',
        '/data/toolchains/flutter/3.47.6/bin/flutter --version --machine',
      ]);
    });

    test('installs the SDK on a miss, then uses it', () async {
      final machine = _Machine();

      final flutter = await resolver(machine).resolve('3.47.6');

      expect(installer.installs, ['3.47.6']);
      expect(flutter.path, '/data/toolchains/flutter/3.47.6');
      expect(flutter.source, FlutterSource.cache);
      expect(flutter.wasInstalled, isTrue);
    });

    test('fails with the reason when the install fails', () async {
      installer.failure = const FlutterInstallException('network is down');

      await expectLater(
        resolver(_Machine()).resolve('3.47.6'),
        throwsA(
          isA<FlutterResolutionException>()
              .having(
                (e) => e.failure,
                'failure',
                FlutterResolutionFailure.installFailed,
              )
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('network is down'),
                  contains('fvm install 3.47.6'),
                ),
              )
              .having((e) => e.tool, 'tool', 'flutter'),
        ),
      );
      expect(installer.installed, isEmpty);
    });

    test('fails when the cached SDK does not run', () async {
      installer.installed.add('3.47.6');
      final machine = _Machine(
        flutterOutput: const ProcessOutput(exitCode: 1, stderr: 'broken'),
      );

      await expectLater(
        resolver(machine).resolve('3.47.6'),
        throwsA(
          isA<FlutterResolutionException>()
              .having(
                (e) => e.failure,
                'failure',
                FlutterResolutionFailure.brokenCache,
              )
              .having(
                (e) => e.fix,
                'fix',
                'Delete /data/toolchains/flutter/3.47.6 and run the job again.',
              ),
        ),
      );
    });

    test('fails when the cached SDK reports another version', () async {
      installer.installed.add('3.47.6');
      final machine = _Machine(
        flutterOutput: const ProcessOutput(
          exitCode: 0,
          stdout: '{"frameworkVersion": "3.47.5"}',
        ),
      );

      await expectLater(
        resolver(machine).resolve('3.47.6'),
        throwsA(
          isA<FlutterResolutionException>().having(
            (e) => e.failure,
            'failure',
            FlutterResolutionFailure.brokenCache,
          ),
        ),
      );
    });

    test('fails when the cached SDK prints nothing readable', () async {
      installer.installed.add('3.47.6');
      final machine = _Machine(
        flutterOutput: const ProcessOutput(exitCode: 0, stdout: 'hello'),
      );

      await expectLater(
        resolver(machine).resolve('3.47.6'),
        throwsA(isA<FlutterResolutionException>()),
      );
    });

    test('fails when the cached SDK cannot be started', () async {
      installer.installed.add('3.47.6');
      final runner = FakeProcessRunner((call) {
        throw ProcessStartException(call.executable, 'gone');
      });

      await expectLater(
        FlutterResolver(runner: runner, installer: installer).resolve('3.47.6'),
        throwsA(
          isA<FlutterResolutionException>().having(
            (e) => e.failure,
            'failure',
            FlutterResolutionFailure.brokenCache,
          ),
        ),
      );
    });

    test('needs an exact version to download', () async {
      await expectLater(
        resolver(_Machine()).resolve('stable', pinSource: 'app/.fvmrc'),
        throwsA(
          isA<FlutterResolutionException>()
              .having(
                (e) => e.failure,
                'failure',
                FlutterResolutionFailure.invalidPin,
              )
              .having((e) => e.fix, 'fix', contains('app/.fvmrc')),
        ),
      );
      await expectLater(
        resolver(_Machine()).resolve('stable'),
        throwsA(
          isA<FlutterResolutionException>().having(
            (e) => e.fix,
            'fix',
            contains('in .fvmrc'),
          ),
        ),
      );
      expect(installer.installs, isEmpty);
    });
  });

  group('the pin', () {
    test('is missing', () async {
      await expectLater(
        resolver(_Machine()).resolve(null),
        throwsA(
          isA<FlutterResolutionException>()
              .having(
                (e) => e.failure,
                'failure',
                FlutterResolutionFailure.noPin,
              )
              .having((e) => e.fix, 'fix', contains('{"flutter": "x.y.z"}')),
        ),
      );
    });

    test('is in a file that cannot be read', () async {
      await expectLater(
        resolver(_Machine()).resolve(null, pinSource: 'app/.fvmrc'),
        throwsA(
          isA<FlutterResolutionException>()
              .having(
                (e) => e.failure,
                'failure',
                FlutterResolutionFailure.invalidPin,
              )
              .having((e) => e.message, 'message', contains('app/.fvmrc')),
        ),
      );
    });

    test('is not a version, so it never reaches a program or a path', () async {
      for (final pin in ['--help', '../../etc', 'a b', '']) {
        final machine = _Machine(fvmList: fixture('fvm_3.2.1_api_list.json'));

        await expectLater(
          resolver(machine).resolve(pin),
          throwsA(
            isA<FlutterResolutionException>().having(
              (e) => e.failure,
              'failure',
              FlutterResolutionFailure.invalidPin,
            ),
          ),
          reason: pin,
        );
        expect(machine.runner.calls, isEmpty, reason: pin);
      }
    });
  });

  test('FlutterResolutionException prints its tool and message', () {
    const error = FlutterResolutionException(
      FlutterResolutionFailure.noPin,
      'No pin.',
      'Add one.',
    );

    expect(error.toString(), 'ToolchainException: flutter: No pin. Add one.');
  });

  test('FlutterInstallException prints its message', () {
    expect(
      const FlutterInstallException('x').toString(),
      'FlutterInstallException: x',
    );
  });
}
