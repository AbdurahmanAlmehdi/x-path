import 'package:xp_engine/src/runners/remote_step_policy.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/scheduler/scheduler_runner.dart';

/// What a [RemoteRunner] asks of the hub that holds the connections.
abstract interface class RemoteLeases {
  /// The slots the runner [runnerId] offers now: none while it drains or
  /// cools off after refusing a job.
  int slotsOf(String runnerId);

  /// Leases the queued job [jobId] to the runner [runnerId] and offers it.
  Future<void> offer(String runnerId, String jobId);

  /// Completes once the lease of [jobId] ended: the job is done, lost,
  /// cancelled or given back.
  Future<void> whenFinished(String jobId);
}

/// A paired runner as the scheduler sees it (D-08, D-19): a machine with the
/// capabilities the engine probed, a number of slots, and jobs it holds a
/// lease for.
///
/// The scheduler places jobs on it like on the local runner; the runner
/// carries a job out only if every step may run remotely
/// ([RemoteStepPolicy]).
class RemoteRunner implements SchedulerRunner {
  /// Creates the runner [id] that can do [capabilities].
  const new({
    required this.id,
    required this.capabilities,
    required this._leases,
  });

  final RemoteLeases _leases;

  @override
  final String id;

  @override
  final Set<Capability> capabilities;

  @override
  int get slots => _leases.slotsOf(id);

  @override
  bool accepts(Iterable<String> stepKinds) =>
      RemoteStepPolicy.canRunRemotely(stepKinds);

  @override
  Future<void> launch(String jobId) => _leases.offer(id, jobId);

  @override
  Future<void> whenFinished(String jobId) => _leases.whenFinished(jobId);
}
