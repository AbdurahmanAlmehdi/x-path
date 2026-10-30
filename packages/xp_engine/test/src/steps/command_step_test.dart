import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

/// A context whose commands end the way the test says.
class _Context implements StepContext {
  new(this.exit);

  ProcessExit exit;
  final commands = <ProcessCommand>[];

  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<String> readDartDefines(String secretKey) =>
      throw StateError('This step reads no define file.');

  @override
  Future<String> writeSecretFile(String name, String contents) =>
      throw StateError('This step writes no secret file.');

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    commands.add(command);
    return exit;
  }
}

void main() {
  const step = CommandStep();

  group('CommandInput', () {
    test('round-trips through JSON', () {
      const input = CommandInput(
        ProcessCommand(
          'flutter',
          arguments: ['build', 'apk'],
          workingDirectory: '/work',
          environment: {'CI': 'true'},
          passThroughEnvironment: ['ANDROID_HOME'],
          secretEnvironment: {'TOKEN': 'github.token'},
          secretFiles: {'KEY_FILE': 'play.sa'},
        ),
        sideEffect: true,
      );

      final read = CommandInput.fromJson(input.toJson());

      expect(read.toJson(), input.toJson());
      expect(read.command.executable, 'flutter');
      expect(read.command.arguments, ['build', 'apk']);
      expect(read.command.workingDirectory, '/work');
      expect(read.command.environment, {'CI': 'true'});
      expect(read.command.passThroughEnvironment, ['ANDROID_HOME']);
      expect(read.command.secretEnvironment, {'TOKEN': 'github.token'});
      expect(read.command.secretFiles, {'KEY_FILE': 'play.sa'});
      expect(read.sideEffect, isTrue);
    });

    test('needs only an executable', () {
      final input = CommandInput.fromJson(const {'executable': 'ls'});

      expect(input.command.arguments, isEmpty);
      expect(input.command.workingDirectory, isNull);
      expect(input.command.environment, isEmpty);
      expect(input.sideEffect, isFalse);
      expect(input.toJson(), isNot(contains('workingDirectory')));
    });

    test('rejects input that is not valid', () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'executable': ''},
        {'executable': 3},
        {'executable': 'x', 'arguments': 'a b'},
        {
          'executable': 'x',
          'arguments': [1],
        },
        {'executable': 'x', 'environment': <String>[]},
        {
          'executable': 'x',
          'environment': {'A': 1},
        },
        {'executable': 'x', 'workingDirectory': 5},
        {'executable': 'x', 'sideEffect': 'yes'},
      ]) {
        expect(
          () => CommandInput.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('CommandStep', () {
    test('is called command and has the side effect the owner declared', () {
      expect(step.kind, 'command');
      expect(step.sideEffectOf(const CommandInput(ProcessCommand('x'))), false);
      expect(
        step.sideEffectOf(
          const CommandInput(ProcessCommand('x'), sideEffect: true),
        ),
        isTrue,
      );
    });

    test('reads and writes its input and result as JSON', () {
      final input = step.decodeInput(const {'executable': 'ls'});

      expect(step.encodeInput(input)['executable'], 'ls');
      expect(step.encodeResult(const CommandResult(0)), {'exitCode': 0});
    });

    test('has no idempotency check', () async {
      final context = _Context(const ProcessExit(exitCode: 0));

      expect(
        await step.alreadyDone(
          const CommandInput(ProcessCommand('x')),
          context,
        ),
        isNull,
      );
    });

    test('succeeds when the command exits with 0', () async {
      final context = _Context(const ProcessExit(exitCode: 0));

      final outcome = await step.run(
        const CommandInput(ProcessCommand('ls', arguments: ['-l'])),
        context,
      );

      expect(outcome, isA<StepSucceeded<CommandResult>>());
      expect((outcome as StepSucceeded<CommandResult>).result.exitCode, 0);
      expect(context.commands.single.arguments, ['-l']);
    });

    test('fails with the exit code when the command fails', () async {
      final context = _Context(const ProcessExit(exitCode: 2));

      final outcome = await step.run(
        const CommandInput(ProcessCommand('make')),
        context,
      );

      expect(outcome, isA<StepFailed>());
      expect((outcome as StepFailed).message, 'make exited with code 2.');
    });

    test('fails when the command was cancelled', () async {
      final context = _Context(
        const ProcessExit(exitCode: -15, cancelled: true),
      );

      final outcome = await step.run(
        const CommandInput(ProcessCommand('make')),
        context,
      );

      expect((outcome as StepFailed).message, 'The command was cancelled.');
    });
  });
}
