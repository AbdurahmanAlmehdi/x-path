import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

const _key = AscKey(keyId: 'K', issuerId: 'I', privateKey: 'p');
const _bundleId = 'com.mataa.app';

AscAppStoreVersion _version(String name, AppVersionState state) =>
    AscAppStoreVersion(
      id: 'v$name',
      versionString: name,
      platform: 'IOS',
      state: state,
    );

ItunesApp _store(String version) =>
    ItunesApp(bundleId: _bundleId, trackId: '1', version: version);

void main() {
  late FakeItunesLookup itunes;
  late FakeAscCredentialSource credentials;
  late FakeAppStoreConnect connect;

  AscAppStoreTrains trains() => AscAppStoreTrains(
    itunes: itunes,
    credentials: credentials,
    connect: (_) => connect,
  );

  Future<AppStoreTrainStatus?> status() =>
      trains().status(bundleId: _bundleId, country: 'sa');

  setUp(() {
    itunes = FakeItunesLookup();
    credentials = FakeAscCredentialSource();
    connect = FakeAppStoreConnect();
  });

  group('an Apple ID flavor (no key): the iTunes lookup only', () {
    test('has the live version of the storefront', () async {
      itunes.answer = _store('5.4.0');

      final result = await status();

      expect(
        result,
        AppStoreTrainStatus(liveVersion: VersionName.parse('5.4.0')),
      );
      expect(itunes.lookups, ['$_bundleId sa']);
      expect(credentials.lookups, [_bundleId]);
    });

    test('has no live version for an app that is not on sale', () async {
      expect(await status(), const AppStoreTrainStatus());
    });

    test('is unreadable when the lookup fails', () async {
      itunes.failure = const ItunesLookupException('down');

      expect(await status(), isNull);
    });

    test('ignores a version it cannot compare', () async {
      itunes.answer = _store('5.4');

      expect(await status(), const AppStoreTrainStatus());
    });
  });

  group('with an API key', () {
    setUp(() {
      credentials.keys[_bundleId] = _key;
      connect.apps[_bundleId] = const AscApp(id: '1', bundleId: _bundleId);
    });

    test(
      'knows the versions that are approved and waiting: closed trains',
      () async {
        connect.versionsOf['1'] = [
          _version('5.4.1', AppVersionState.pendingDeveloperRelease),
          _version('5.4.0', AppVersionState.readyForDistribution),
          _version('5.3.0', AppVersionState.replacedWithNewVersion),
          _version('5.5.0', AppVersionState.waitingForReview),
          _version('junk', AppVersionState.readyForDistribution),
        ];
        itunes.answer = _store('5.4.0');

        final result = await status();

        expect(result!.liveVersion, VersionName.parse('5.4.0'));
        expect(result.closedVersions, {VersionName.parse('5.4.1')});
      },
    );

    test('takes the higher live version of the two sources', () async {
      connect.versionsOf['1'] = [
        _version('5.4.2', AppVersionState.readyForDistribution),
      ];
      itunes.answer = _store('5.4.0');

      expect((await status())!.liveVersion, VersionName.parse('5.4.2'));

      itunes.answer = _store('5.9.0');
      expect((await status())!.liveVersion, VersionName.parse('5.9.0'));
    });

    test('works without the iTunes lookup', () async {
      itunes.failure = const ItunesLookupException('down');
      connect.versionsOf['1'] = [
        _version('5.4.0', AppVersionState.readyForDistribution),
      ];

      expect((await status())!.liveVersion, VersionName.parse('5.4.0'));
    });

    test('falls back to the lookup when App Store Connect fails', () async {
      itunes.answer = _store('5.4.0');
      connect.failure = const AscAuthException('revoked');

      expect((await status())!.liveVersion, VersionName.parse('5.4.0'));
    });

    test('is unreadable when both sources fail', () async {
      itunes.failure = const ItunesLookupException('down');
      connect.failure = const AscServerException(500, 'down');

      expect(await status(), isNull);
    });

    test(
      'has nothing to say about an app the team does not have yet',
      () async {
        connect.apps.clear();
        itunes.failure = const ItunesLookupException('down');

        expect(await status(), const AppStoreTrainStatus());
        expect(connect.calls, ['findApp $_bundleId']);
      },
    );
  });

  group('against the fake ASC server', () {
    late FakeAscServer server;
    late ManualClock clock;

    setUp(() async {
      clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
      server = await FakeAscServer.start(now: clock.now);
      addTearDown(server.close);
    });

    test('finds the closed train of the 90186 incident', () async {
      final app = server.addApp(_bundleId);
      server
        ..addVersion(app.id, '5.4.0', appVersionState: 'READY_FOR_DISTRIBUTION')
        ..addVersion(
          app.id,
          '5.4.1',
          appVersionState: 'PENDING_DEVELOPER_RELEASE',
        )
        ..addItunes(_bundleId, version: '5.4.0', country: 'sa');
      final lookup = HttpItunesLookup(baseUrl: server.baseUrl, clock: clock);
      addTearDown(lookup.close);
      final trains = AscAppStoreTrains(
        itunes: lookup,
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
      );

      final result = await trains.status(bundleId: _bundleId, country: 'sa');

      expect(result!.liveVersion, VersionName.parse('5.4.0'));
      expect(result.closedVersions, {VersionName.parse('5.4.1')});
      expect(server.requests.where((r) => r.tokenProblem != null), isEmpty);
    });
  });
}
