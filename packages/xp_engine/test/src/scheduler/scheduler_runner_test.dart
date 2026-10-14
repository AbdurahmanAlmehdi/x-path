import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

void main() {
  test('a quarter of the cores, at least one', () {
    expect(defaultSlots(1), 1);
    expect(defaultSlots(3), 1);
    expect(defaultSlots(4), 1);
    expect(defaultSlots(8), 2);
    expect(defaultSlots(10), 2);
    expect(defaultSlots(32), 8);
  });

  test(
    'the local runner is the engine, with the capabilities it was given',
    () {
      final harness = JobHarness.create();
      final runner = LocalRunner(
        jobs: harness.runner,
        capabilities: const {Capability.flutter},
        slots: 3,
      );

      expect(runner.id, localRunnerId);
      expect(localRunnerId, 'local');
      expect(runner.capabilities, {Capability.flutter});
      expect(runner.slots, 3);
    },
  );

  test('the local runner starts a job and says when it ended', () async {
    final harness = JobHarness.create();
    final runner = LocalRunner(
      jobs: harness.runner,
      capabilities: const {},
      slots: 1,
    );
    final job = await harness.create([harness.script()]);

    await runner.launch(job.id);
    await runner.whenFinished(job.id);

    expect((await harness.runner.get(job.id)).state, JobState.succeeded);
  });

  test('a capability is found by its wire name', () {
    expect(Capability.fromWire('ios-sign'), Capability.iosSign);
    expect(Capability.fromWire('swift-linux'), Capability.swiftLinux);
    expect(Capability.fromWire('lasers'), isNull);
    expect(Capability.values.map((c) => c.wire), [
      'ios-sign',
      'android',
      'flutter',
      'swift-linux',
    ]);
  });
}
