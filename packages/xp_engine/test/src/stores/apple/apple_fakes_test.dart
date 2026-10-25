// Equality needs two separate objects, which `const` would make one.
// ignore_for_file: prefer_const_constructors

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

const _key = AscKey(keyId: 'K', issuerId: 'I', privateKey: 'p');

void main() {
  group('FakeAppStoreConnect', () {
    late FakeAppStoreConnect connect;

    setUp(() {
      connect = FakeAppStoreConnect();
      connect.apps['a.b'] = const AscApp(id: '1', bundleId: 'a.b');
    });

    test('finds apps and records the call', () async {
      expect((await connect.findApp('a.b'))!.id, '1');
      expect(await connect.findApp('x'), isNull);
      expect(connect.calls, ['findApp a.b', 'findApp x']);
    });

    test('filters builds by version and number', () async {
      connect.buildsOf['1'] = const [
        AscBuild(
          id: 'b1',
          buildNumber: '44',
          version: '1.0.0',
          processingState: AscProcessingState.valid,
        ),
        AscBuild(
          id: 'b2',
          buildNumber: '45',
          version: '1.0.0',
          processingState: AscProcessingState.processing,
        ),
        AscBuild(
          id: 'b3',
          buildNumber: '45',
          version: '1.1.0',
          processingState: AscProcessingState.valid,
        ),
      ];

      Future<List<String>> ids({String? version, String? number}) async => [
        for (final b in await connect.builds(
          '1',
          version: version,
          buildNumber: number,
        ))
          b.id,
      ];

      expect(await ids(), ['b1', 'b2', 'b3']);
      expect(await ids(version: '1.0.0'), ['b1', 'b2']);
      expect(await ids(number: '45'), ['b2', 'b3']);
      expect(await ids(version: '1.1.0', number: '45'), ['b3']);
      expect(await connect.builds('2'), isEmpty);
    });

    test('lists versions and submissions', () async {
      connect.versionsOf['1'] = const [
        AscAppStoreVersion(
          id: 'v',
          versionString: '1.0.0',
          platform: 'IOS',
          state: AppVersionState.readyForDistribution,
        ),
      ];

      expect(await connect.versions('1'), hasLength(1));
      expect(await connect.versions('2'), isEmpty);
      expect(await connect.reviewSubmissions('1'), isEmpty);
    });

    test('creates, submits and reads a review submission', () async {
      final created = await connect.createReviewSubmission('1', 'v');

      expect(created.state, ReviewSubmissionState.readyForReview);
      expect(await connect.reviewSubmissions('1'), [created]);

      final submitted = await connect.submitReviewSubmission(created.id);

      expect(submitted.state, ReviewSubmissionState.waitingForReview);
      expect(submitted.submittedDate, isNotNull);
      expect(await connect.reviewSubmission(created.id), submitted);
    });

    test('has no submission it was not given', () {
      expect(
        () => connect.submitReviewSubmission('nope'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => connect.reviewSubmission('nope'),
        throwsA(isA<StateError>()),
      );
    });

    test('reads and moves a phased release', () async {
      connect.phasedReleases['v'] = const AscPhasedRelease(
        id: 'p',
        state: PhasedReleaseState.active,
        currentDayNumber: 2,
      );

      expect((await connect.phasedRelease('v'))!.currentDayNumber, 2);
      expect(await connect.phasedRelease('other'), isNull);

      final paused = await connect.updatePhasedRelease(
        'p',
        PhasedReleaseState.paused,
      );

      expect(paused.state, PhasedReleaseState.paused);
      expect(paused.currentDayNumber, 2);
      expect(
        (await connect.phasedRelease('v'))!.state,
        PhasedReleaseState.paused,
      );
    });

    test('throws the failure it was given once', () async {
      connect.failure = const AscAuthException('no');

      await expectLater(
        connect.findApp('a.b'),
        throwsA(isA<AscAuthException>()),
      );
      expect(await connect.findApp('a.b'), isNotNull);
    });

    test('keeps the bytes of an upload and completes it by default', () async {
      final upload = await connect.uploadBuild(
        '1',
        version: '1.0.0',
        buildNumber: '7',
        fileName: 'a.ipa',
        length: 3,
        content: () => Stream.fromIterable([
          [1],
          [2, 3],
        ]),
      );

      expect(upload.state, AscBuildUploadState.processing);
      expect(connect.uploads[upload.id], [1, 2, 3]);
      expect(
        await connect.buildUpload(upload.id),
        AscBuildUpload(
          id: upload.id,
          state: AscBuildUploadState.complete,
          buildId: 'build-of-${upload.id}',
        ),
      );
      expect(connect.calls, [
        'uploadBuild 1 1.0.0 7 a.ipa 3',
        'buildUpload ${upload.id}',
      ]);
    });

    test(
      'answers the upload states it was given, the last one again',
      () async {
        const processing = AscBuildUpload(
          id: 'u',
          state: AscBuildUploadState.processing,
        );
        const failed = AscBuildUpload(
          id: 'u',
          state: AscBuildUploadState.failed,
        );
        connect.uploadAnswers.addAll([processing, failed]);

        expect(await connect.buildUpload('u'), processing);
        expect(await connect.buildUpload('u'), failed);
        expect(await connect.buildUpload('u'), failed);
      },
    );

    test('reports the rate limit it was given', () {
      connect.rateLimit = const AscRateLimit(limit: 10, remaining: 9);

      expect(connect.rateLimit!.remaining, 9);
    });
  });

  group('FakeItunesLookup', () {
    test('answers and records the call', () async {
      final lookup = FakeItunesLookup(
        const ItunesApp(bundleId: 'a.b', trackId: '1', version: '1.0.0'),
      );

      expect(
        (await lookup.lookup(bundleId: 'a.b', country: 'sa'))!.trackId,
        '1',
      );
      expect(lookup.lookups, ['a.b sa']);
    });

    test('is empty by default and fails once when told to', () async {
      final lookup = FakeItunesLookup()
        ..failure = const ItunesLookupException('down');

      await expectLater(
        lookup.lookup(bundleId: 'a', country: 'us'),
        throwsA(isA<ItunesLookupException>()),
      );
      expect(await lookup.lookup(bundleId: 'a', country: 'us'), isNull);
    });

    test('prints its failure', () {
      expect(
        const ItunesLookupException('down').toString(),
        'ItunesLookupException: down',
      );
    });

    test('describes an app by value', () {
      final first = ItunesApp(bundleId: 'a', trackId: '1', version: '1.0.0');
      final second = ItunesApp(bundleId: 'a', trackId: '1', version: '1.0.0');

      expect(first, second);
    });
  });

  group('FakeAscCredentialSource', () {
    test('answers by bundle id and records the call', () async {
      final source = FakeAscCredentialSource({'a.b': _key});

      expect(await source.forBundleId('a.b'), _key);
      expect(await source.forBundleId('x'), isNull);
      expect(source.lookups, ['a.b', 'x']);
    });

    test('starts empty', () async {
      expect(await FakeAscCredentialSource().forBundleId('a.b'), isNull);
    });
  });
}
