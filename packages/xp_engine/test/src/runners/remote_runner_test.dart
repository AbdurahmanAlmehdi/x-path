import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('RemoteRunner', () {
    test('is a scheduler runner that follows the hub', () async {
      final leases = _Leases();
      final runner = RemoteRunner(
        id: 'rnr_1',
        capabilities: const {Capability.android},
        leases: leases,
      );

      expect(runner.id, 'rnr_1');
      expect(runner.capabilities, {Capability.android});
      expect(runner.slots, 3);
      expect(runner.accepts(['build.android']), isTrue);
      expect(runner.accepts(['upload.play']), isFalse);
      await runner.launch('job_1');
      await runner.whenFinished('job_2');
      expect(leases.calls, ['offer rnr_1 job_1', 'finished job_2']);
    });
  });
}

class _Leases implements RemoteLeases {
  final calls = <String>[];

  @override
  int slotsOf(String runnerId) => 3;

  @override
  Future<void> offer(String runnerId, String jobId) async =>
      calls.add('offer $runnerId $jobId');

  @override
  Future<void> whenFinished(String jobId) async => calls.add('finished $jobId');
}
