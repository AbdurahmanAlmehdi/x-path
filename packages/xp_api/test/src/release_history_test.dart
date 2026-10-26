import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 26, 9);

  test('the kinds and the patch actions use snake_case on the wire', () {
    expect(ReleaseEventKind.values.map((kind) => kind.wire), [
      'created',
      'build',
      'store',
      'merge_requested',
      'merged',
      'abandoned',
      'rollout_requested',
      'rollout',
      'patch',
      'patch_requested',
      'patch_promoted',
      'patch_rolled_back',
      'texts',
    ]);
    expect(PatchAction.values.map((action) => action.wire), [
      'promote',
      'rollback',
    ]);
  });

  test('an event leaves out what it lacks, and round-trips', () {
    final created = ReleaseEvent(kind: ReleaseEventKind.created, at: at);
    final promoted = ReleaseEvent(
      kind: ReleaseEventKind.patchPromoted,
      at: at,
      store: ReleaseStore.play,
      detail: 'stable',
      by: 'MacBook',
      runId: 'run_3',
      patchNumber: 2,
    );

    expect(created.toJson(), {
      'kind': 'created',
      'at': '2026-10-26T09:00:00.000Z',
    });
    final history = ReleaseHistory([created, promoted]);
    expect(ReleaseHistory.fromJson(history.toJson()), history);
  });

  test('the texts leave out what they lack and refuse a wrong type', () {
    const texts = ReleaseTexts(whatsNew: 'New', whatToTest: 'Try it');

    expect(const ReleaseTexts().toJson(), isEmpty);
    expect(ReleaseTexts.fromJson(texts.toJson()), texts);
    expect(
      () => ReleaseTexts.fromJson(const {'whatsNew': 5}),
      throwsA(isA<CheckedFromJsonException>()),
    );
  });
}
