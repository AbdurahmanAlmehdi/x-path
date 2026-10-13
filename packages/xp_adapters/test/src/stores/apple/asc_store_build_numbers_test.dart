import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

const _key = AscKey(keyId: 'K', issuerId: 'I', privateKey: 'p');
const _bundleId = 'com.mataa.app';

AscBuild _build(String number, {String? version}) => AscBuild(
  id: 'b$number',
  buildNumber: number,
  version: version,
  processingState: AscProcessingState.valid,
);

void main() {
  late FakeAscCredentialSource credentials;
  late FakeAppStoreConnect connect;

  AscStoreBuildNumbers numbers() =>
      AscStoreBuildNumbers(credentials: credentials, connect: (_) => connect);

  setUp(() {
    credentials = FakeAscCredentialSource({_bundleId: _key});
    connect = FakeAppStoreConnect()
      ..apps[_bundleId] = const AscApp(id: '1', bundleId: _bundleId);
  });

  test('collects the build numbers of every train, expired or not', () async {
    connect.buildsOf['1'] = [
      _build('3281', version: '5.4.0'),
      _build('3283', version: '5.4.1'),
      _build('3282.1'),
      _build('x'),
    ];

    final builds = await numbers().lookup(iosBundleId: _bundleId);

    expect(builds, const StoreBuilds({3281, 3283}));
    expect(builds!.highest, 3283);
  });

  test(
    'cannot be asked without an iOS bundle id (Play is not Apple)',
    () async {
      expect(await numbers().lookup(androidAppId: 'com.mataa.app'), isNull);
      expect(credentials.lookups, isEmpty);
    },
  );

  test('cannot be asked without a key (an Apple ID flavor)', () async {
    credentials.keys.clear();

    expect(await numbers().lookup(iosBundleId: _bundleId), isNull);
  });

  test('has no builds for an app the team does not have yet', () async {
    connect.apps.clear();

    expect(
      await numbers().lookup(iosBundleId: _bundleId),
      const StoreBuilds({}),
    );
  });

  test('cannot be asked when App Store Connect fails', () async {
    connect.failure = const AscRateLimitedException('wait');

    expect(await numbers().lookup(iosBundleId: _bundleId), isNull);
  });

  test('reads the builds from the fake ASC server', () async {
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    final server = await FakeAscServer.start(now: clock.now);
    addTearDown(server.close);
    final app = server.addApp(_bundleId);
    server
      ..addBuild(app.id, buildNumber: '3282', version: '5.4.0')
      ..addBuild(app.id, buildNumber: '3283', version: '5.4.1');

    final result = await AscStoreBuildNumbers(
      credentials: FakeAscCredentialSource({
        _bundleId: const AscKey(
          keyId: fakeAscKeyId,
          issuerId: fakeAscIssuerId,
          privateKey: fakeAscPrivateKeyPem,
        ),
      }),
      connect: (key) {
        final client = HttpAppStoreConnect(
          key: key,
          clock: clock,
          baseUrl: server.baseUrl,
        );
        addTearDown(client.close);
        return client;
      },
    ).lookup(iosBundleId: _bundleId);

    expect(result, const StoreBuilds({3282, 3283}));
  });
}
