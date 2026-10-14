import 'package:xp_engine/src/jobs/job_runner.dart';
import 'package:xp_engine/src/scheduler/capability.dart';

/// A place where jobs run: a machine with capabilities and slots (D-19).
///
/// The `Scheduler` decides which job goes to which runner and when; the runner
/// only carries it out. The engine is a runner itself ([LocalRunner]). Remote
/// runners (`RemoteRunner`) implement the same interface: they take a job with
/// a lease and heartbeats, report [capabilities] the engine probed itself, and
/// finish a job when its lease ends or it reports back.
abstract interface class SchedulerRunner {
  /// The id the runner is known by. The jobs it runs name it as their
  /// `runnerId`; the local runner is `local` and leaves it empty.
  String get id;

  /// What the runner can do, as the engine probed it.
  Set<Capability> get capabilities;

  /// How many jobs run at once; `ios-sign` jobs run one at a time whatever
  /// this is.
  int get slots;

  /// Whether this runner may run a job made of steps of [stepKinds]. The
  /// engine runs everything; a remote runner never runs the steps that need
  /// what only the engine has (`RemoteStepPolicy`).
  bool accepts(Iterable<String> stepKinds);

  /// Starts the queued job [jobId] on this runner, which runs it in the
  /// background.
  Future<void> launch(String jobId);

  /// Completes once [jobId] is no longer running on this runner.
  Future<void> whenFinished(String jobId);
}

/// Where jobs that run on remote runners are cancelled: the engine cannot stop
/// their processes itself, so the runner is told and the job ends at once.
abstract interface class RemoteJobs {
  /// Cancels the job [id] if a remote runner holds its lease and returns
  /// whether it did. A job that runs elsewhere is left alone.
  Future<bool> cancel(String id);
}

/// How many jobs the engine runs at once by default: a quarter of the
/// processor cores, and at least one (D-19).
int defaultSlots(int processors) => processors ~/ 4 < 1 ? 1 : processors ~/ 4;

/// The id of the runner that is the engine itself.
const localRunnerId = 'local';

/// The engine as a runner: it runs the jobs with its own `JobRunner`.
class LocalRunner implements SchedulerRunner {
  /// Creates the runner with the [capabilities] the engine found on this
  /// machine and [slots] jobs at a time.
  const new({
    required this._jobs,
    required this.capabilities,
    required this.slots,
  }) : assert(slots > 0, 'A runner has at least one slot.');

  final JobRunner _jobs;

  @override
  String get id => localRunnerId;

  @override
  final Set<Capability> capabilities;

  @override
  final int slots;

  @override
  bool accepts(Iterable<String> stepKinds) => true;

  @override
  Future<void> launch(String jobId) async {
    await _jobs.start(jobId);
  }

  @override
  Future<void> whenFinished(String jobId) async {
    await _jobs.whenFinished(jobId);
  }
}
