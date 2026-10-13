import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';
import 'package:xp_engine/src/toolchain/job_tools.dart';
import 'package:xp_engine/src/toolchain/tool_prober.dart';

/// Decides which tools a build runs with and records them for the job (D-20).
class BuildToolchain {
  /// Creates the toolchain over the resolver and the prober of Phase 9a.
  const new({
    required this._resolver,
    required this._prober,
    required this._jobs,
  });

  final FlutterResolver _resolver;
  final ToolProber _prober;
  final JobRepository _jobs;

  /// The Flutter SDK for the pin [flutterVersion] (`.fvmrc`), with the tool
  /// versions of this machine saved for the job [jobId].
  ///
  /// Throws a `FlutterResolutionException` if there is no SDK for the pin.
  Future<ResolvedFlutter> prepare(String jobId, String? flutterVersion) async {
    final flutter = await _resolver.resolve(flutterVersion);
    final reports = await _prober.probeAll();
    await _jobs.saveTools(
      jobId,
      JobTools.from(flutter: flutter, reports: reports),
    );
    return flutter;
  }

  /// The tool versions saved for the job [jobId], or `null` if none were.
  Future<JobTools?> recorded(String jobId) => _jobs.tools(jobId);
}
