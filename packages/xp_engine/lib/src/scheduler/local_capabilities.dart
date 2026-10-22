import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/runners/probe_executor.dart';
import 'package:xp_engine/src/runners/runner_probe.dart';

/// What this machine can do (D-19): the engine asks the tools instead of
/// trusting a setting.
///
/// It runs the commands of [RunnerProbe] with its own processes and reads
/// them with the same rules as a runner's, so the engine and a runner on the
/// same machine find the same capabilities, and say the same about the ones
/// they lack.
class LocalCapabilities {
  /// Creates the probe for a machine running [operatingSystem] (`macos` or
  /// `linux`).
  const new({
    required this._runner,
    required this.operatingSystem,
    this._probe = const RunnerProbe(),
  });

  final ProcessRunner _runner;
  final RunnerProbe _probe;

  /// `macos` or `linux`.
  final String operatingSystem;

  /// Probes the machine.
  Future<ProbeFindings> probe() async {
    final results = await ProbeExecutor(
      runner: _runner,
      operatingSystem: operatingSystem,
    ).run(_probe.commands);
    return _probe.evaluate(results);
  }
}
