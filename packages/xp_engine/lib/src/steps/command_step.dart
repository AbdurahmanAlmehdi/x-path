import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// A command the owner declared in a workflow.
class CommandInput {
  /// Creates the input.
  const new(this.command, {this.sideEffect = false});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if [json] lacks `executable` or has a field
  /// of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final executable = json['executable'];
    if (executable is! String || executable.isEmpty) {
      throw const FormatException('A command needs an "executable".');
    }
    final workingDirectory = json['workingDirectory'];
    final sideEffect = json['sideEffect'];
    if (workingDirectory is! String? || sideEffect is! bool?) {
      throw const FormatException(
        '"workingDirectory" must be a string and "sideEffect" a boolean.',
      );
    }
    return CommandInput(
      ProcessCommand(
        executable,
        arguments: _strings(json, 'arguments'),
        workingDirectory: workingDirectory,
        environment: _stringMap(json, 'environment'),
        passThroughEnvironment: _strings(json, 'passThroughEnvironment'),
        secretEnvironment: _stringMap(json, 'secretEnvironment'),
        secretFiles: _stringMap(json, 'secretFiles'),
      ),
      sideEffect: sideEffect ?? false,
    );
  }

  /// What to run.
  final ProcessCommand command;

  /// Whether the owner declared that the command changes something outside
  /// the engine.
  final bool sideEffect;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'executable': command.executable,
    'arguments': command.arguments,
    if (command.workingDirectory != null)
      'workingDirectory': command.workingDirectory,
    'environment': command.environment,
    'passThroughEnvironment': command.passThroughEnvironment,
    'secretEnvironment': command.secretEnvironment,
    'secretFiles': command.secretFiles,
    'sideEffect': sideEffect,
  };

  static List<String> _strings(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return const [];
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw FormatException('"$field" must be a list of strings.');
  }

  static Map<String, String> _stringMap(
    Map<String, dynamic> json,
    String field,
  ) {
    final value = json[field];
    if (value == null) return const {};
    if (value is Map && value.values.every((item) => item is String)) {
      return value.cast<String, String>();
    }
    throw FormatException('"$field" must be an object of strings.');
  }
}

/// What a [CommandStep] produced.
class CommandResult {
  /// Creates the result.
  const new(this.exitCode);

  /// The exit code, 0.
  final int exitCode;
}

/// Runs a command the owner declared (`command` in the step library).
///
/// The owner says whether it has side effects. It has no idempotency check:
/// after an interruption the owner decides whether to run it again.
class CommandStep extends Step<CommandInput, CommandResult> {
  /// Creates the step.
  const new();

  @override
  String get kind => 'command';

  @override
  bool sideEffectOf(CommandInput input) => input.sideEffect;

  @override
  CommandInput decodeInput(Map<String, dynamic> json) =>
      CommandInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(CommandInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(CommandResult result) => {
    'exitCode': result.exitCode,
  };

  @override
  Future<StepOutcome<CommandResult>> run(
    CommandInput input,
    StepContext context,
  ) async {
    final exit = await context.run(input.command);
    if (exit.cancelled) return const StepFailed('The command was cancelled.');
    if (!exit.succeeded) {
      return StepFailed(
        '${input.command.executable} exited with code '
        '${exit.exitCode}.',
      );
    }
    return StepSucceeded(CommandResult(exit.exitCode));
  }
}
