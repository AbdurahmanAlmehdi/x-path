import 'package:test/test.dart';
import 'package:xp/src/runner/job/lease_paths.dart';
import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/job/remote_checkout_step.dart';
import 'package:xp/src/runner/no_secrets.dart';
import 'package:xp/src/runner/runner_steps.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late RunnerSteps steps;
  late LeaseServices services;

  setUp(() {
    final runner = FakeProcessRunner(
      (call) => const ProcessOutput(exitCode: 0),
    );
    steps = RunnerSteps(
      runner: runner,
      git: CliGitService(
        runner: runner,
        secrets: const NoSecrets(),
        dataDir: '/tmp/xp-runner-test',
      ),
      clock: ManualClock(DateTime.utc(2026)),
      flutterToolchains: '/tmp/xp-runner-test/toolchains',
      isMacOS: true,
      queues: SerialQueues(),
    );
    services = LeaseServices(
      jobs: InMemoryJobRepository(),
      secrets: const NoSecrets(),
      artifacts: InMemoryArtifactRepository(),
      artifactStore: InMemoryArtifactStore(),
      source: const LeaseSource(),
      paths: const LeasePaths({}),
    );
  });

  test('makes a registry of exactly the kinds a runner declares', () {
    expect(steps.registry(services).kinds.toSet(), RunnerSteps.kinds);
  });

  test('only has steps the engine lets a runner run', () {
    expect(RemoteStepPolicy.engineOnlyIn(RunnerSteps.kinds), isEmpty);
  });

  test('has every step a build job of the built-in workflows is made of', () {
    const buildJobKinds = {
      'git.checkout',
      'version.bump',
      'build.android',
      'build.ios',
      'shorebird.release',
      'shorebird.patch',
      'symbols.archive',
      'record.manifest',
      'build.verifyCompiledConfig',
      'ios.stripAndReexport',
    };

    expect(RunnerSteps.kinds.containsAll(buildJobKinds), isTrue);
  });

  test("checks out with the runner's own step, not the engine's", () {
    final checkout = steps.registry(services)['git.checkout'];

    expect(checkout, isA<RemoteCheckoutStep>());
  });

  test('makes a new registry, with new records, for each lease', () {
    expect(
      identical(steps.registry(services), steps.registry(services)),
      isFalse,
    );
  });
}
