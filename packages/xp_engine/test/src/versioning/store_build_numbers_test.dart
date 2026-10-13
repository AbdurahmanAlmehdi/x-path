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
}
