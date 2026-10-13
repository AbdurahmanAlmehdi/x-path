import 'package:xp_engine/src/steps/step.dart';

/// The step types the engine can run, by kind.
class StepRegistry {
  /// Creates a registry of [steps].
  ///
  /// Throws an [ArgumentError] if two steps have the same kind.
  new(Iterable<Step<Object?, Object?>> steps) : _steps = {} {
    for (final step in steps) {
      if (_steps.containsKey(step.kind)) {
        throw ArgumentError.value(step.kind, 'steps', 'Duplicate step kind');
      }
      _steps[step.kind] = step;
    }
  }

  final Map<String, Step<Object?, Object?>> _steps;

  /// The step of [kind], or `null` if the engine has none.
  Step<Object?, Object?>? operator [](String kind) => _steps[kind];

  /// The kinds the registry knows.
  Iterable<String> get kinds => _steps.keys;
}
