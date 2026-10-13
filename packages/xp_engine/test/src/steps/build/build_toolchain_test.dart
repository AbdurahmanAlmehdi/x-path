import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

void main() {
  late BuildHarness harness;

  setUp(() async {
    harness = BuildHarness(isMacOS: true);
    await harness.createJob();
  });

  test('resolves Flutter and records the versions for the job', () async {
    final flutter = await harness.toolchain.prepare('job_1', '3.47.6');

    expect(
      flutter.flutterExecutable,
      '/data/toolchains/flutter/3.47.6/bin/flutter',
    );
    expect(
      await harness.toolchain.recorded('job_1'),
      const JobTools(flutter: '3.47.6', dart: '3.13.5', xcode: '27.1'),
    );
  });

  test('has no versions before a build', () async {
    expect(await harness.toolchain.recorded('job_1'), isNull);
  });

  test('fails with a fix when the pin is missing', () async {
    await expectLater(
      harness.toolchain.prepare('job_1', null),
      throwsA(isA<FlutterResolutionException>()),
    );
  });
}
