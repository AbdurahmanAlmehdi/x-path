import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

const _account = PlayServiceAccount(clientEmail: 'a@b.c', privateKey: 'k');

void main() {
  late FakePlayCredentialSource credentials;
  late FakeGooglePlay play;
  late PlayStoreBuildNumbers numbers;

  setUp(() {
    credentials = FakePlayCredentialSource({'com.mataa.app': _account});
    play = FakeGooglePlay();
    numbers = PlayStoreBuildNumbers(
      credentials: credentials,
      connect: (_) => play,
    );
  });

  test('is every version code of the bundles of the app', () async {
    play.bundlesOnPlay.addAll(const [
      PlayBundle(versionCode: 3280),
      PlayBundle(versionCode: 3283),
    ]);

    final builds = await numbers.lookup(
      iosBundleId: 'com.mataa.ios',
      androidAppId: 'com.mataa.app',
    );

    expect(builds, const StoreBuilds({3280, 3283}));
    expect(play.calls, [
      'insertEdit com.mataa.app',
      'bundles com.mataa.app edit-1',
      'deleteEdit com.mataa.app edit-1',
    ]);
  });

  test('is empty for an app without bundles', () async {
    expect(
      await numbers.lookup(androidAppId: 'com.mataa.app'),
      const StoreBuilds({}),
    );
  });

  test('is null for an app without an Android application id', () async {
    expect(await numbers.lookup(iosBundleId: 'com.mataa.ios'), isNull);
    expect(credentials.lookups, isEmpty);
  });

  test('is null without a service account', () async {
    expect(await numbers.lookup(androidAppId: 'com.other'), isNull);
    expect(play.calls, isEmpty);
  });

  test('is null when Play refuses, and the edit is still deleted', () async {
    play.failures['bundles'] = const PlayForbiddenException('no');

    expect(await numbers.lookup(androidAppId: 'com.mataa.app'), isNull);
    expect(play.deleted, ['edit-1']);
  });

  test('is null when no edit can be opened', () async {
    play.failures['insertEdit'] = const PlayNotFoundException('no such app');

    expect(await numbers.lookup(androidAppId: 'com.mataa.app'), isNull);
    expect(play.deleted, isEmpty);
  });

  test('does not depend on the edit being deleted', () async {
    play
      ..bundlesOnPlay.add(const PlayBundle(versionCode: 5))
      ..failures['deleteEdit'] = const PlayServerException(503, 'down');

    expect(
      await numbers.lookup(androidAppId: 'com.mataa.app'),
      const StoreBuilds({5}),
    );
  });
}
