import 'package:xp_engine/xp_engine.dart';

import 'build_harness.dart';
import 'fake_build_directories.dart';
import 'fake_snapshot_reader.dart';
import 'fakes.dart';
import 'job_harness.dart';
import 'local_artifact_store.dart';

/// Every step type a workflow can use, built over fakes: enough to plan a
/// step, which asks the step to read its input, and to run the ones that
/// touch git. [git] is what the git steps use.
StepRegistry allSteps({
  GitService? git,
  JobRepository? jobs,
  ApprovalGate gate = const PendingApprovalGate(),
}) {
  final harness = BuildHarness(isMacOS: true);
  final repository = jobs ?? harness.jobs;
  final service = git ?? FakeGitService();
  final directories = FakeBuildDirectories();
  final records = InMemoryShorebirdReleaseRepository();
  final releases = FakeShorebirdReleases();
  final store = LocalInMemoryArtifactStore();
  final secrets = MemorySecretStore();
  final events = InMemoryEventLog(clock: harness.clock);
  Never connect(Object? _) => throw UnimplementedError();
  Workspace workspace(String _) => InMemoryWorkspace({});
  return StepRegistry([
    const CommandStep(),
    GateStep(gate),
    GitCheckoutStep(git: service, jobs: repository),
    GitReleaseBranchStep(service),
    GitTagStep(service),
    GitPushStep(service),
    GitHubCreatePrStep(FakeGitHubClient({})),
    GitHubMergePrStep(
      github: FakeGitHubClient({}),
      releases: InMemoryReleaseRepository(),
    ),
    VersionBumpStep(git: service, workspaces: workspace),
    BuildAndroidStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
    ),
    BuildIosStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
      isMacOS: true,
    ),
    ShorebirdReleaseStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
      releases: releases,
      records: records,
      clock: harness.clock,
      isMacOS: true,
    ),
    ShorebirdPatchStep(
      toolchain: harness.toolchain,
      files: harness.files,
      releases: releases,
      records: records,
      isMacOS: true,
    ),
    SymbolsArchiveStep(
      directories: directories,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
    ),
    VerifyCompiledConfigStep(
      workspaces: workspace,
      repository: harness.artifacts,
      store: harness.store,
      snapshots: FakeSnapshotReader(),
    ),
    StripAndReexportStep(
      directories: directories,
      files: harness.files,
      recorder: harness.recorder,
      isMacOS: true,
    ),
    RecordManifestStep(
      git: service,
      workspaces: workspace,
      artifacts: harness.artifacts,
      recorder: harness.recorder,
      jobs: repository,
      clock: harness.clock,
    ),
    TestStep(
      toolchain: harness.toolchain,
      jobs: repository,
      runs: InMemoryTestRunRepository(),
      events: events,
      clock: harness.clock,
    ),
    AnalyzeStep(toolchain: harness.toolchain),
    UploadAppStoreStep(
      repository: harness.artifacts,
      store: store,
      secrets: secrets,
      secretFiles: InMemorySecretFileStore(),
      connect: connect,
      isMacOS: true,
    ),
    UploadPlayStep(
      repository: harness.artifacts,
      store: store,
      secrets: secrets,
      connect: connect,
    ),
    UploadFirebaseStep(
      repository: harness.artifacts,
      store: store,
      secrets: secrets,
      connect: connect,
    ),
    GuardStep(
      checks: const [SourceCheck(), VersionSyncCheck()],
      git: service,
      workspaces: workspace,
    ),
  ]);
}
