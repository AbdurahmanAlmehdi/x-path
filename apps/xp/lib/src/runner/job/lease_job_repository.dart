import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Hears about a step of the leased job that reached a new state.
typedef StepReport = void Function(StepRecord step);

/// The job a runner executes, kept in memory for the length of the lease.
///
/// The job runner of the engine writes the state of every step to its
/// `JobRepository`. A runner has no database: this repository keeps the one
/// job, and passes each change of a step on to the engine as a `step_state`
/// frame ([onStep]), once per new state of an attempt, and to the journal of
/// process groups ([onProcessGroup]).
class LeaseJobRepository extends InMemoryJobRepository {
  /// Creates the repository.
  new({required this.onStep, required this.onProcessGroup});

  /// Hears about each new state of a step.
  final StepReport onStep;

  /// Hears about the process group of the process a step runs, `null` when
  /// it ended.
  final void Function(String jobId, int ordinal, int? pgid) onProcessGroup;

  final _reported = <String, (StepState, int)>{};

  @override
  Future<void> updateStep(StepRecord step) async {
    await super.updateStep(step);
    onProcessGroup(step.jobId, step.ordinal, step.pgid);
    final key = '${step.jobId}/${step.ordinal}';
    final seen = (step.state, step.attempts);
    if (step.state == StepState.pending || _reported[key] == seen) return;
    _reported[key] = seen;
    onStep(step);
  }
}
