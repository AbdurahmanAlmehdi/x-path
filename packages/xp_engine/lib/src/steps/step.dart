import 'package:xp_engine/src/steps/step_context.dart';

/// How a step ended.
sealed class StepOutcome<R> {
  const new();
}

/// The step did its work and produced [result].
final class StepSucceeded<R> extends StepOutcome<R> {
  /// Creates the outcome.
  const new(this.result);

  /// What the step produced.
  final R result;
}

/// The step could not do its work. The job stops here.
final class StepFailed extends StepOutcome<Never> {
  /// Creates the outcome.
  const new(this.message);

  /// Why, for the owner. Never contains a secret.
  final String message;
}

/// The step cannot go on until someone decides (D-13): a gate waits for the
/// owner to approve an action. The job stops here, holding no slot, and goes
/// on when it is resumed; the step runs again then and asks again.
final class StepWaiting extends StepOutcome<Never> {
  /// Creates the outcome.
  const new(this.reason);

  /// What the step waits for, for the owner.
  final String reason;
}

/// The step had nothing to do.
final class StepSkipped extends StepOutcome<Never> {
  /// Creates the outcome.
  const new(this.reason);

  /// Why.
  final String reason;
}

/// One kind of step of a job, with typed input [I] and result [R].
///
/// A step records its completion in the job, so that a job that is run again
/// resumes at the first step that is not done (D-18). The engine stores the
/// input and the result as JSON, which is how a job survives a restart.
abstract class Step<I, R> {
  /// Creates a step.
  const new();

  /// The name of the step type, stored with the job. Unique per registry.
  String get kind;

  /// Whether running the step with [input] changes something outside the
  /// engine: a store upload, a push, a tag. The engine never repeats such a
  /// step on its own after it was interrupted.
  bool sideEffectOf(I input);

  /// Reads the input from the JSON the job stored.
  ///
  /// Throws a [FormatException] if [json] is not a valid input.
  I decodeInput(Map<String, dynamic> json);

  /// The JSON to store for [input].
  Map<String, dynamic> encodeInput(I input);

  /// The JSON to store for [result].
  Map<String, dynamic> encodeResult(R result);

  /// Asks the outside world whether the work of this step exists already, for
  /// example whether a store has the build. Returns what the step would have
  /// produced, or `null` if the work is not done.
  ///
  /// The engine calls it before a step with side effects runs again after an
  /// earlier attempt, and skips the step if it returns a result.
  Future<R?> alreadyDone(I input, StepContext context) async => null;

  /// Does the work.
  ///
  /// An exception is a failure of the step with its message, as if the step
  /// had returned [StepFailed].
  Future<StepOutcome<R>> run(I input, StepContext context);
}

/// A step of a job that is about to be created: the kind and the stored input.
class StepPlan {
  /// Creates a plan from the stored form.
  const new({
    required this.kind,
    required this.input,
    required this.sideEffect,
  });

  /// Plans [step] with [input].
  static StepPlan of<I>(Step<I, Object?> step, I input) => StepPlan(
    kind: step.kind,
    input: step.encodeInput(input),
    sideEffect: step.sideEffectOf(input),
  );

  /// The step type.
  final String kind;

  /// The input as JSON.
  final Map<String, dynamic> input;

  /// Whether the step has side effects.
  final bool sideEffect;
}
