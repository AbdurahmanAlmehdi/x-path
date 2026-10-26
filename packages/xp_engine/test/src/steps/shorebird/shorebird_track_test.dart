import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/step_context.dart';

void main() {
  late FakeShorebirdPatches patches;
  late ShorebirdTrackStep step;
  final context = NoProcessContext();

  final input = ShorebirdTrackInput(
    shorebirdAppId: 'app-1',
    releaseVersion: AppVersion.parse('1.2.0+5'),
    patchNumber: 2,
    action: PatchAction.promote,
    tokenSecret: 'shorebird.prod',
  );

  setUp(() {
    patches = FakeShorebirdPatches();
    step = ShorebirdTrackStep(patches);
  });

  test('keeps its input and result in their stored form', () {
    expect(step.kind, 'shorebird.track');
    expect(step.sideEffectOf(input), isTrue);
    expect(step.decodeInput(step.encodeInput(input)), input);
    expect(input.props, hasLength(5));
    expect(
      step.encodeResult(
        const ShorebirdTrackResult(
          patchNumber: 2,
          action: PatchAction.rollback,
        ),
      ),
      {'patchNumber': 2, 'action': 'rollback'},
    );
    expect(
      const ShorebirdTrackResult(
        patchNumber: 2,
        action: PatchAction.promote,
      ).props,
      [2, PatchAction.promote],
    );
  });

  test('refuses an input without a patch or with an unknown action', () {
    final json = input.toJson();

    for (final bad in [
      {...json, 'patchNumber': 0},
      {...json, 'patchNumber': '2'},
      {...json, 'action': 'delete'},
    ]) {
      expect(() => step.decodeInput(bad), throwsFormatException);
    }
  });

  test('promotes and rolls back the patch', () async {
    final promoted = await step.run(input, context);
    final rolledBack = await step.run(
      ShorebirdTrackInput(
        shorebirdAppId: 'app-1',
        releaseVersion: AppVersion.parse('1.2.0+5'),
        patchNumber: 2,
        action: PatchAction.rollback,
      ),
      context,
    );

    expect(
      (promoted as StepSucceeded<ShorebirdTrackResult>).result,
      const ShorebirdTrackResult(patchNumber: 2, action: PatchAction.promote),
    );
    expect(rolledBack, isA<StepSucceeded<ShorebirdTrackResult>>());
    expect(patches.changes, [
      'promote app-1 1.2.0+5 2',
      'rollback app-1 1.2.0+5 2',
    ]);
  });

  test('says what Shorebird said when it did not', () async {
    patches.failure = 'No patch 2.';

    final outcome = await step.run(input, context);

    expect((outcome as StepFailed).message, 'Shorebird: No patch 2.');
    expect(
      const ShorebirdPatchesException('x').toString(),
      'ShorebirdPatchesException: x',
    );
  });
}
