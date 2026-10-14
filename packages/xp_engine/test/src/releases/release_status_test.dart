import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final at = DateTime.utc(2026, 10, 14, 9);

  ReleaseRecord release({String version = '1.2.0', int build = 5}) =>
      ReleaseRecord(
        id: 'rel_1',
        projectId: 'prj_1',
        appPath: '.',
        flavor: 'prod',
        version: version,
        build: build,
        state: ReleaseState.uploaded,
        stores: const {},
        builds: [ReleaseBuild(build: build, runId: 'run_1', createdAt: at)],
        baseBranch: 'main',
        createdAt: at,
        updatedAt: at,
      );

  const appleEntry = StoreEntry(
    store: ReleaseStore.apple,
    state: StoreState.uploaded,
    source: StatusSource.upload,
    identity: {
      'bundleId': 'ly.demo',
      'appleAppId': '1234567890',
      'country': 'us',
    },
  );
  const playEntry = StoreEntry(
    store: ReleaseStore.play,
    state: StoreState.uploaded,
    source: StatusSource.upload,
    identity: {'packageName': 'ly.demo', 'track': 'internal'},
  );

  test('a reading and a poll are values', () {
    StoreReading make() => const StoreReading(
      state: StoreState.live,
      source: StatusSource.api,
      detail: 'X',
    );

    expect(make(), make());
    expect(
      StorePoll(reading: make(), note: 'n'),
      StorePoll(reading: make(), note: 'n'),
    );
    expect(
      make(),
      isNot(const StoreReading(source: StatusSource.api, detail: 'X')),
    );
  });

  group('AppleStatusSource', () {
    late FakeAscCredentialSource credentials;
    late FakeAppStoreConnect connect;
    late FakeItunesLookup itunes;
    late AppleStatusSource source;
    const key = AscKey(keyId: 'KEY', issuerId: 'issuer', privateKey: 'pem');

    setUp(() {
      credentials = FakeAscCredentialSource({'ly.demo': key});
      connect = FakeAppStoreConnect();
      itunes = FakeItunesLookup();
      source = AppleStatusSource(
        credentials: credentials,
        connect: (_) => connect,
        itunes: itunes,
      );
      connect.apps['ly.demo'] = const AscApp(
        id: '1234567890',
        bundleId: 'ly.demo',
      );
    });

    AscAppStoreVersion version(String name, AppVersionState state) =>
        AscAppStoreVersion(
          id: 'v_$name',
          versionString: name,
          platform: 'IOS',
          state: state,
        );

    Future<StoreReading?> read([ReleaseRecord? record]) =>
        source.read(record ?? release(), appleEntry);

    test('is apple', () => expect(source.store, ReleaseStore.apple));

    test('maps every version state of App Store Connect', () async {
      final expected = <AppVersionState, StoreState?>{
        AppVersionState.prepareForSubmission: null,
        AppVersionState.readyForReview: null,
        AppVersionState.waitingForExportCompliance: null,
        AppVersionState.waitingForReview: StoreState.inReview,
        AppVersionState.inReview: StoreState.inReview,
        AppVersionState.accepted: StoreState.approved,
        AppVersionState.pendingDeveloperRelease: StoreState.approved,
        AppVersionState.pendingAppleRelease: StoreState.approved,
        AppVersionState.pendingContract: StoreState.approved,
        AppVersionState.processingForAppStore: StoreState.approved,
        AppVersionState.readyForDistribution: StoreState.live,
        AppVersionState.preorderReadyForSale: StoreState.live,
        AppVersionState.rejected: StoreState.rejected,
        AppVersionState.metadataRejected: StoreState.rejected,
        AppVersionState.invalidBinary: StoreState.rejected,
        AppVersionState.developerRejected: StoreState.rejected,
        AppVersionState.developerRemovedFromSale: null,
        AppVersionState.removedFromSale: null,
        AppVersionState.replacedWithNewVersion: null,
        AppVersionState.unknown: null,
      };
      for (final MapEntry(key: state, value: store) in expected.entries) {
        connect.versionsOf['1234567890'] = [version('1.2.0', state)];

        final reading = await read();

        expect(reading!.state, store, reason: state.name);
        expect(reading.source, StatusSource.api);
        expect(
          reading.detail,
          state == AppVersionState.unknown ? 'UNKNOWN' : state.wire,
        );
      }
      expect(credentials.lookups.toSet(), {'ly.demo'});
      expect(itunes.lookups, isEmpty);
    });

    test('reads the version of the release, not another', () async {
      connect.versionsOf['1234567890'] = [
        version('1.3.0', AppVersionState.prepareForSubmission),
        version('1.2.0', AppVersionState.inReview),
      ];

      expect((await read())!.state, StoreState.inReview);
    });

    test('says when there is no such version yet', () async {
      connect.versionsOf['1234567890'] = [
        version('1.1.0', AppVersionState.readyForDistribution),
      ];

      final reading = await read();

      expect(reading!.state, isNull);
      expect(reading.detail, 'App Store Connect has no version 1.2.0 yet.');
    });

    test('says when the team has no such app', () async {
      connect.apps.clear();

      final reading = await read();

      expect(reading!.state, isNull);
      expect(reading.detail, contains('no app with bundle id ly.demo'));
    });

    test('lets the failures of App Store Connect through', () async {
      connect.failure = const AppStoreConnectException(401, 'expired');

      await expectLater(read(), throwsA(isA<AppStoreConnectException>()));
    });

    group('without an API key (an Apple ID flavor)', () {
      setUp(() => credentials.keys.clear());

      test('is live when the version is on sale in the storefront', () async {
        itunes.answer = const ItunesApp(
          bundleId: 'ly.demo',
          trackId: '1234567890',
          version: '1.2.0',
        );

        final reading = await read();

        expect(reading!.state, StoreState.live);
        expect(reading.source, StatusSource.lookup);
        expect(reading.detail, 'On sale: 1.2.0');
        expect(itunes.lookups, ['ly.demo us']);
        expect(connect.calls, isEmpty);
      });

      test('is live when a higher version is on sale', () async {
        itunes.answer = const ItunesApp(
          bundleId: 'ly.demo',
          trackId: '1',
          version: '1.3.1',
        );

        expect((await read())!.state, StoreState.live);
      });

      test('says nothing while a lower version is on sale', () async {
        itunes.answer = const ItunesApp(
          bundleId: 'ly.demo',
          trackId: '1',
          version: '1.1.9',
        );

        final reading = await read();

        expect(reading!.state, isNull);
        expect(reading.detail, 'On sale: 1.1.9');
      });

      test('says nothing about a version it cannot read', () async {
        itunes.answer = const ItunesApp(
          bundleId: 'ly.demo',
          trackId: '1',
          version: 'beta',
        );

        expect((await read())!.state, isNull);
      });

      test('says when the storefront does not have the app', () async {
        final reading = await read();

        expect(reading!.state, isNull);
        expect(reading.detail, 'Not on sale in the us storefront.');
      });

      test('lets the failures of the lookup through', () async {
        itunes.failure = const ItunesLookupException('down');

        await expectLater(read(), throwsA(isA<ItunesLookupException>()));
      });
    });
  });

  group('PlayStatusSource', () {
    late FakePlayCredentialSource credentials;
    late FakeGooglePlay play;
    late PlayStatusSource source;

    setUp(() {
      credentials = FakePlayCredentialSource({
        'ly.demo': const PlayServiceAccount(
          clientEmail: 'sa@example.iam.gserviceaccount.com',
          privateKey: 'pem',
          tokenUri: 'https://oauth2.example/token',
        ),
      });
      play = FakeGooglePlay();
      source = PlayStatusSource(credentials: credentials, connect: (_) => play);
    });

    Future<StoreReading?> read([int build = 5]) =>
        source.read(release(build: build), playEntry);

    test('is play', () => expect(source.store, ReleaseStore.play));

    test('maps every lifecycle state', () async {
      final expected = <PlayLifecycleState, StoreState?>{
        PlayLifecycleState.draft: null,
        PlayLifecycleState.notSentForReview: null,
        PlayLifecycleState.inReview: StoreState.inReview,
        PlayLifecycleState.approvedNotPublished: StoreState.approved,
        PlayLifecycleState.notApproved: StoreState.rejected,
        PlayLifecycleState.published: StoreState.live,
        PlayLifecycleState.unknown: null,
      };
      for (final MapEntry(key: state, value: store) in expected.entries) {
        play.releasesOf['internal'] = [
          PlayReleaseSummary(
            track: 'internal',
            state: state,
            versionCodes: const [5],
          ),
        ];

        final reading = await read();

        expect(reading!.state, store, reason: state.name);
        expect(reading.source, StatusSource.api);
        expect(
          reading.detail,
          state == PlayLifecycleState.unknown ? 'UNKNOWN' : state.wire,
        );
      }
      expect(play.calls.first, 'releases ly.demo internal');
    });

    test('finds the release that holds the version code', () async {
      play.releasesOf['internal'] = const [
        PlayReleaseSummary(
          track: 'internal',
          state: PlayLifecycleState.published,
          versionCodes: [4],
        ),
        PlayReleaseSummary(
          track: 'internal',
          state: PlayLifecycleState.inReview,
          versionCodes: [5, 6],
        ),
      ];

      expect((await read())!.state, StoreState.inReview);
    });

    test('says when no release holds the version code', () async {
      final reading = await read(9);

      expect(reading!.state, isNull);
      expect(
        reading.detail,
        'Google Play has no release with version code 9 on the internal track.',
      );
    });

    test('cannot read an app without a service account', () async {
      credentials.accounts.clear();

      expect(await read(), isNull);
      expect(play.calls, isEmpty);
    });
  });

  group('ReleaseStatusPoller', () {
    late ManualClock clock;
    late FakeStoreStatusSource apple;
    late ReleaseStatusPoller poller;

    setUp(() {
      clock = ManualClock(at);
      apple = FakeStoreStatusSource(ReleaseStore.apple);
      poller = ReleaseStatusPoller(sources: [apple], clock: clock);
    });

    test('is due when never asked, and every ten minutes after', () {
      expect(poller.cacheFor, const Duration(minutes: 10));
      expect(poller.isDue(appleEntry), isTrue);
      final asked = appleEntry.copyWith(checkedAt: at);
      expect(poller.isDue(asked), isFalse);
      clock.advance(const Duration(minutes: 9, seconds: 59));
      expect(poller.isDue(asked), isFalse);
      clock.advance(const Duration(seconds: 1));
      expect(poller.isDue(asked), isTrue);
    });

    test('hands back what the store said', () async {
      const said = StoreReading(
        state: StoreState.live,
        source: StatusSource.api,
        detail: 'READY_FOR_DISTRIBUTION',
      );
      apple.reading = said;

      final poll = await poller.poll(release(), appleEntry);

      expect(poll, const StorePoll(reading: said));
      expect(apple.reads, ['rel_1 5']);
    });

    test('says how to go on when a store cannot be read', () async {
      expect(
        (await poller.poll(release(), appleEntry)).note,
        contains('Apple approved'),
      );
      final play = ReleaseStatusPoller(
        sources: [FakeStoreStatusSource(ReleaseStore.play)],
        clock: clock,
      );
      expect(
        (await play.poll(release(), playEntry)).note,
        contains('Play: live'),
      );
    });

    test('says when it has no source for a store', () async {
      final poll = await poller.poll(release(), playEntry);

      expect(poll.reading, isNull);
      expect(poll.note, 'This engine cannot read play yet.');
    });

    test('reports a store that fails and does not throw', () async {
      for (final (failure, note) in <(Object, String)>[
        (
          const AppStoreConnectException(401, 'expired'),
          'App Store Connect: expired',
        ),
        (const ItunesLookupException('down'), 'iTunes lookup: down'),
        (const PlayException(500, 'oops'), 'Google Play: oops'),
      ]) {
        apple.failure = failure;

        expect((await poller.poll(release(), appleEntry)).note, note);
      }
    });

    test('does not hide a failure that is not a store failure', () async {
      apple.failure = StateError('bug');

      await expectLater(poller.poll(release(), appleEntry), throwsStateError);
    });
  });
}
