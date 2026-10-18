import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/command_runner.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/update/update_check.dart';
import 'package:xp/src/version.dart';

import '../helpers/test_env.dart';

class _MockLogger extends Mock implements Logger;

class _FlaggedCommand extends Command<int> {
  new() {
    argParser.addFlag('flag', negatable: false);
  }

  @override
  String get name => 'flagged';

  @override
  String get description => 'A command with a flag.';

  @override
  Future<int> run() async => ExitCode.success.code;
}

void main() {
  group('XpCommandRunner', () {
    late Logger logger;
    late XpCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();
      commandRunner = XpCommandRunner(logger: logger);
    });

    test('can be instantiated without an explicit logger', () {
      final commandRunner = XpCommandRunner();
      expect(commandRunner, isNotNull);
      expect(commandRunner, isA<CompletionCommandRunner<int>>());
    });

    test('handles the completion command', () async {
      final result = await commandRunner.run(['completion']);
      expect(result, equals(ExitCode.success.code));
    });

    test('handles FormatException', () async {
      const exception = FormatException('oops!');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version', () async {
        final result = await commandRunner.run(['--version']);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info(packageVersion)).called(1);
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await commandRunner.run(['--verbose']);
        expect(result, equals(ExitCode.success.code));

        verify(() => logger.detail('Argument information:')).called(1);
        verify(() => logger.detail('  Top level options:')).called(1);
        verify(() => logger.detail('  - verbose: true')).called(1);
        verifyNever(() => logger.detail('    Command options:'));
      });

      test('enables verbose logging for sub commands', () async {
        commandRunner.addCommand(_FlaggedCommand());
        final result = await commandRunner.run([
          '--verbose',
          'flagged',
          '--flag',
        ]);
        expect(result, equals(ExitCode.success.code));

        verify(() => logger.detail('Argument information:')).called(1);
        verify(() => logger.detail('  Top level options:')).called(1);
        verify(() => logger.detail('  - verbose: true')).called(1);
        verify(() => logger.detail('  Command: flagged')).called(1);
        verify(() => logger.detail('    Command options:')).called(1);
        verify(() => logger.detail('    - flag: true')).called(1);
      });
    });

    group('a context of its own', () {
      late TestEnv env;

      setUp(() => env = TestEnv());
      tearDown(() => env.dispose());

      test('shows every command in its usage, and the exit codes', () async {
        final usage = env.runner.usage;

        for (final command in [
          'connect',
          'projects',
          'credentials',
          'workflows',
          'dispatch',
          'runs',
          'jobs',
          'logs',
          'approvals',
          'gates',
          'releases',
          'storage',
          'artifacts',
          'mcp',
        ]) {
          expect(usage, contains(command), reason: command);
        }
        expect(usage, contains('Exit codes:'));
        expect(usage, contains('78  not connected'));
        expect(usage, contains('XP_NO_UPDATE_CHECK=1'));
      });

      test('prints the help of every command', () async {
        final paths = <List<String>>[];
        void walk(Map<String, Command<int>> commands, List<String> prefix) {
          for (final entry in commands.entries) {
            // `help` and the completion commands print on their own.
            if (prefix.isEmpty &&
                (entry.key == 'help' || entry.key.contains('completion'))) {
              continue;
            }
            // An alias prints the usage of the command it stands for.
            if (entry.key != entry.value.name) continue;
            paths.add([...prefix, entry.key]);
            walk(entry.value.subcommands, [...prefix, entry.key]);
          }
        }

        walk(env.runner.commands, []);

        expect(paths.length, greaterThan(40));
        for (final path in paths) {
          env.logger.infos.clear();
          expect(await env.run([...path, '--help']), 0, reason: '$path');
          expect(env.logger.out, contains('Usage: xp ${path.join(' ')}'));
        }
      });

      test('pairs and revokes runners', () {
        expect(
          env.runner.commands['runners']!.subcommands.keys,
          unorderedEquals(['pair', 'revoke']),
        );
      });

      test('prints the usage of a group', () async {
        expect(await env.run(['projects']), 64);

        expect(env.logger.errors.single, contains('Missing subcommand'));
        expect(env.logger.out, contains('Usage: xp projects <subcommand>'));
        expect(env.logger.out, contains('scan'));
      });

      test('says when a newer release exists, on standard error', () async {
        env.update.newer = '9.9.9';
        when(() => env.client.listProjects()).thenAnswer((_) async => []);

        await env.runOk(['projects', 'list']);

        expect(env.update.calls, 1);
        expect(env.logger.warnings.single, contains('9.9.9'));
        expect(env.logger.warnings.single, contains(packageVersion));
      });

      test('says nothing when there is nothing newer', () async {
        when(() => env.client.listProjects()).thenAnswer((_) async => []);

        await env.runOk(['projects', 'list']);

        expect(env.update.calls, 1);
        expect(env.logger.warnings, isEmpty);
      });

      test('does not look for an update for JSON output', () async {
        env.update.newer = '9.9.9';
        when(() => env.client.listProjects()).thenAnswer((_) async => []);

        await env.runOk(['--json', 'projects', 'list']);

        expect(env.update.calls, 0);
        expect(env.logger.warnings, isEmpty);
      });

      test('does not look for an update without a command', () async {
        await env.runOk(['--version']);

        expect(env.update.calls, 0);
      });

      test('never waits long for the update check', () async {
        final stuck = Completer<String?>();
        final slow = _SlowUpdateCheck(stuck.future);
        final context = XpContext(
          logger: env.logger,
          config: env.config,
          environment: env.environment,
          clientFactory: env.context.clientFactory,
          updateCheck: slow,
          stdin: const Stream.empty(),
          stdout: env.stdout,
        );
        when(() => env.client.listProjects()).thenAnswer((_) async => []);
        final runner = XpCommandRunner(context: context);

        final watch = Stopwatch()..start();
        expect(await runner.run(['projects', 'list']), 0);
        watch.stop();

        expect(slow.calls, 1);
        expect(watch.elapsedMilliseconds, lessThan(2000));
        expect(env.logger.warnings, isEmpty);
        stuck.complete();
      });
    });
  });
}

class _SlowUpdateCheck implements UpdateCheck {
  new(this._result);

  final Future<String?> _result;
  int calls = 0;

  @override
  Future<String?> newerVersion() {
    calls++;
    return _result;
  }
}
