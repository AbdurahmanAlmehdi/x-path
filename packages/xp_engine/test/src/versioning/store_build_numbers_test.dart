import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('the highest build is the largest, and 0 for none', () {
    expect(const StoreBuilds({3280, 3283, 12}).highest, 3283);
    expect(const StoreBuilds({}).highest, 0);
  });

  test('the fake answers what it was given and records the calls', () async {
    final fake = FakeStoreBuildNumbers(const StoreBuilds({1}));

    expect(
      await fake.lookup(
        iosBundleId: 'com.mataa.app',
        androidAppId: 'com.mataa',
      ),
      const StoreBuilds({1}),
    );
    fake.builds = null;
    expect(await fake.lookup(), isNull);
    expect(fake.lookups, ['com.mataa.app com.mataa', 'null null']);
  });

  group('CombinedStoreBuildNumbers', () {
    late FakeStoreBuildNumbers apple;
    late FakeStoreBuildNumbers play;
    late CombinedStoreBuildNumbers combined;

    setUp(() {
      apple = FakeStoreBuildNumbers(const StoreBuilds({3280, 3282}));
      play = FakeStoreBuildNumbers(const StoreBuilds({3281, 3282}));
      combined = CombinedStoreBuildNumbers(apple: apple, play: play);
    });

    test(
      'joins the builds of both stores, each asked for its own app',
      () async {
        final builds = await combined.lookup(
          iosBundleId: 'com.mataa.app',
          androidAppId: 'com.mataa.android',
        );

        expect(builds, const StoreBuilds({3280, 3281, 3282}));
        expect(apple.lookups, ['com.mataa.app null']);
        expect(play.lookups, ['null com.mataa.android']);
      },
    );

    test('asks only the store the app is on', () async {
      expect(
        await combined.lookup(iosBundleId: 'com.mataa.app'),
        const StoreBuilds({3280, 3282}),
      );
      expect(
        await combined.lookup(androidAppId: 'com.mataa.android'),
        const StoreBuilds({3281, 3282}),
      );
      expect(apple.lookups, hasLength(1));
      expect(play.lookups, hasLength(1));
    });

    test('names the store it could not read and keeps the other', () async {
      play.builds = null;

      final builds = await combined.lookup(
        iosBundleId: 'com.mataa.app',
        androidAppId: 'com.mataa.android',
      );

      expect(
        builds,
        const StoreBuilds({3280, 3282}, unreadable: {'Google Play'}),
      );

      apple.builds = null;
      play.builds = const StoreBuilds({1});
      expect(
        await combined.lookup(
          iosBundleId: 'com.mataa.app',
          androidAppId: 'com.mataa.android',
        ),
        const StoreBuilds({1}, unreadable: {'App Store Connect'}),
      );
    });

    test('is null when no store could be read or the app is on none', () async {
      apple.builds = null;
      play.builds = null;

      expect(
        await combined.lookup(
          iosBundleId: 'com.mataa.app',
          androidAppId: 'com.mataa.android',
        ),
        isNull,
      );
      expect(await combined.lookup(), isNull);
    });
  });
}
