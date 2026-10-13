import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/guard_harness.dart';

void main() {
  final full = guardRequest(
    checks: GuardCheckName.values,
    releaseVersion: '5.4.1+3283',
    shorebirdAppId: 'sb-1',
  ).request.input;

  test('round-trips through JSON', () {
    expect(GuardInput.fromJson(full.toJson()), full);
  });

  test('round-trips the flavor and the credential kinds', () {
    final input = guardRequest(
      checks: [GuardCheckName.credentials],
      flavorId: 'flv_1',
      credentialKinds: [CredentialKind.ascKey, CredentialKind.firebaseSa],
    ).request.input;

    expect(input.toJson()['flavorId'], 'flv_1');
    expect(input.toJson()['credentialKinds'], ['asc_key', 'firebase_sa']);
    expect(GuardInput.fromJson(input.toJson()), input);
  });

  test('refuses a credential kind that does not exist', () {
    final json = full.toJson()..['credentialKinds'] = ['dropbox'];

    expect(() => GuardInput.fromJson(json), throwsFormatException);
  });

  test('keeps the store countries', () {
    final json = full.toJson()..['storeCountry'] = 'ae';

    expect(GuardInput.fromJson(json).storeCountry, 'ae');
  });

  test('needs only the checks and the worktree', () {
    final json = {
      'checks': ['source'],
      'worktree': full.worktree.toJson(),
    };
    final input = GuardInput.fromJson(json);

    expect(input.checks, [GuardCheckName.source]);
    expect(input.releaseVersion, isNull);
    expect(input.iosBundleId, isNull);
    expect(input.androidAppId, isNull);
    expect(input.shorebirdAppId, isNull);
    expect(input.storeCountry, 'us');
    expect(input.toJson(), isNot(contains('releaseVersion')));
    expect(input.flavorId, isNull);
    expect(input.credentialKinds, isEmpty);
    expect(input.toJson(), isNot(contains('flavorId')));
    expect(input.toJson(), isNot(contains('credentialKinds')));
  });

  test('names every check of the step library', () {
    expect(GuardCheckName.values.map((name) => name.name), [
      'source',
      'appStoreTrain',
      'versionSync',
      'patchTarget',
      'newReleaseNumber',
      'patchNativeDiff',
      'playTargetSdk',
      'buildNumberReuse',
      'credentials',
    ]);
  });

  test('rejects input that is not valid', () {
    final worktree = full.worktree.toJson();
    for (final json in <Map<String, dynamic>>[
      {'checks': 'source', 'worktree': worktree},
      {
        'checks': ['nope'],
        'worktree': worktree,
      },
      {'checks': <String>[]},
      {'checks': <String>[], 'worktree': worktree, 'releaseVersion': 5},
    ]) {
      expect(() => GuardInput.fromJson(json), throwsFormatException);
    }
  });
}
