import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

const _key = AscKey(
  keyId: fakeAscKeyId,
  issuerId: fakeAscIssuerId,
  privateKey: fakeAscPrivateKeyPem,
);

void main() {
  late ManualClock clock;
  late FakeAscServer server;
  late List<Duration> sleeps;

  HttpAppStoreConnect client({
    AscKey key = _key,
    http.Client? httpClient,
    Uri? baseUrl,
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final created = HttpAppStoreConnect(
      key: key,
      clock: clock,
      client: httpClient,
      baseUrl: baseUrl ?? server.baseUrl,
      maxAttempts: maxAttempts,
      timeout: timeout,
      sleep: (duration) async => sleeps.add(duration),
    );
    addTearDown(created.close);
    return created;
  }

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    sleeps = [];
    server = await FakeAscServer.start(now: clock.now);
    addTearDown(server.close);
  });

  group('verifyAccess', () {
    test('reads one app with the key', () async {
      server
        ..addApp('ly.example.app')
        ..addApp('ly.example.other');

      await client().verifyAccess();

      final request = server.requests.single;
      expect(request.uri.path, '/v1/apps');
      expect(request.uri.queryParameters['limit'], '1');
      expect(request.tokenProblem, isNull);
    });

    test('is a 401 for a key Apple does not know', () async {
      final error = await client(
        key: const AscKey(
          keyId: 'OTHERKEY01',
          issuerId: fakeAscIssuerId,
          privateKey: fakeAscPrivateKeyPem,
        ),
      ).verifyAccess().then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<AscAuthException>());
    });
  });

  group('the bearer token', () {
    test('is a valid team token on every call', () async {
      server.addApp('ly.example.app');

      await client().findApp('ly.example.app');

      expect(server.requests.single.tokenProblem, isNull);
    });

    test(
      'is refused with a fix when the key is not the one registered',
      () async {
        server.addApp('ly.example.app');

        final error =
            await client(
                  key: const AscKey(
                    keyId: 'OTHERKEY01',
                    issuerId: fakeAscIssuerId,
                    privateKey: fakeAscPrivateKeyPem,
                  ),
                )
                .findApp('ly.example.app')
                .then<Object?>((_) => null, onError: (Object e) => e);

        expect(error, isA<AscAuthException>());
        final exception = error! as AscAuthException;
        expect(exception.message, 'The key id OTHERKEY01 is unknown.');
        expect(exception.code, 'NOT_AUTHORIZED');
        expect(exception.fix, contains('key id'));
      },
    );

    test('cannot be made from a private key that is not a .p8', () async {
      final api = client(
        key: const AscKey(keyId: 'K', issuerId: 'I', privateKey: 'nope'),
      );

      await expectLater(
        api.findApp('a.b'),
        throwsA(
          isA<AscAuthException>().having(
            (e) => e.message,
            'message',
            allOf(contains('cannot be used'), isNot(contains('nope'))),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('is renewed as time passes', () async {
      server.addApp('ly.example.app');
      final api = client();

      await api.findApp('ly.example.app');
      clock.advance(const Duration(hours: 2));
      await api.findApp('ly.example.app');

      expect(server.requests.map((r) => r.tokenProblem), [null, null]);
    });
  });

  group('findApp', () {
    test('finds the app by bundle id', () async {
      final app = server.addApp('ly.example.app', id: '777', name: 'Example');
      server.addApp('ly.example.other');

      expect(
        await client().findApp('ly.example.app'),
        AscApp(id: app.id, bundleId: 'ly.example.app', name: 'Example'),
      );
      final uri = server.requests.single.uri;
      expect(uri.path, '/v1/apps');
      expect(uri.queryParameters['filter[bundleId]'], 'ly.example.app');
    });

    test('is null for an app the team does not have', () async {
      expect(await client().findApp('ly.example.none'), isNull);
    });
  });

  group('builds', () {
    late FakeAscApp app;

    setUp(() {
      app = server.addApp('ly.example.app');
    });

    test('are read with their train and processing state', () async {
      server
        ..addBuild(
          app.id,
          buildNumber: '3282',
          version: '5.4.0',
          expired: true,
          uploadedDate: DateTime.utc(2026, 9),
        )
        ..addBuild(
          app.id,
          buildNumber: '3283',
          version: '5.4.1',
          processingState: 'PROCESSING',
          uploadedDate: DateTime.utc(2026, 10, 12),
        );

      final builds = await client().builds(app.id);

      expect(builds.map((b) => b.buildNumber), ['3283', '3282']);
      expect(builds.first.version, '5.4.1');
      expect(builds.first.processingState, AscProcessingState.processing);
      expect(builds.first.uploadedDate, DateTime.utc(2026, 10, 12));
      expect(builds.last.expired, isTrue);
      expect(builds.last.processingState, AscProcessingState.valid);
      final query = server.requests.single.uri.queryParameters;
      expect(query['filter[app]'], app.id);
      expect(query['include'], 'preReleaseVersion');
      expect(query['sort'], '-uploadedDate');
      expect(query.containsKey('filter[version]'), isFalse);
    });

    test('are filtered by version and build number', () async {
      server
        ..addBuild(app.id, buildNumber: '3283', version: '5.4.1')
        ..addBuild(app.id, buildNumber: '3283', version: '5.4.2')
        ..addBuild(app.id, buildNumber: '3284', version: '5.4.1');

      final builds = await client().builds(
        app.id,
        version: '5.4.1',
        buildNumber: '3283',
      );

      expect(builds.map((b) => '${b.version}+${b.buildNumber}'), [
        '5.4.1+3283',
      ]);
      final query = server.requests.single.uri.queryParameters;
      expect(query['filter[preReleaseVersion.version]'], '5.4.1');
      expect(query['filter[version]'], '3283');
    });

    test('follow links.next to the last page', () async {
      for (var i = 1; i <= 450; i++) {
        server.addBuild(app.id, buildNumber: '$i', version: '5.4.1');
      }

      final builds = await client().builds(app.id);

      expect(builds, hasLength(450));
      expect(server.requests, hasLength(3));
      expect(server.requests.map((r) => r.uri.queryParameters['cursor']), [
        null,
        '200',
        '400',
      ]);
    });
  });

  group('versions', () {
    test('are read from appVersionState, newest first', () async {
      final app = server.addApp('ly.example.app');
      server
        ..addVersion(
          app.id,
          '5.4.0',
          appVersionState: 'READY_FOR_DISTRIBUTION',
          createdDate: DateTime.utc(2026, 8),
        )
        ..addVersion(
          app.id,
          '5.4.1',
          appVersionState: 'PENDING_DEVELOPER_RELEASE',
          createdDate: DateTime.utc(2026, 9),
        )
        ..addVersion(
          app.id,
          '5.5.0',
          appVersionState: 'BRAND_NEW_STATE',
          createdDate: DateTime.utc(2026, 10),
        );

      final versions = await client().versions(app.id);

      expect(versions.map((v) => v.versionString), ['5.5.0', '5.4.1', '5.4.0']);
      expect(versions.map((v) => v.state), [
        AppVersionState.unknown,
        AppVersionState.pendingDeveloperRelease,
        AppVersionState.readyForDistribution,
      ]);
      expect(versions.last.platform, 'IOS');
      expect(versions.last.createdDate, DateTime.utc(2026, 8));
      expect(
        server.requests.single.uri.queryParameters['filter[platform]'],
        'IOS',
      );
    });

    test('of an app that is not there is a 404', () async {
      await expectLater(
        client().versions('missing'),
        throwsA(isA<AscNotFoundException>()),
      );
    });
  });

  group('review submissions', () {
    late FakeAscApp app;
    late FakeAscVersion version;

    setUp(() {
      app = server.addApp('ly.example.app');
      version = server.addVersion(app.id, '5.4.1');
    });

    test('are created with the version, submitted and read', () async {
      final api = client();

      final created = await api.createReviewSubmission(app.id, version.id);

      expect(created.state, ReviewSubmissionState.readyForReview);
      expect(created.platform, 'IOS');
      expect(server.submissions[created.id]!.versionIds, [version.id]);
      expect(server.requests.map((r) => r.toString()), [
        'POST /v1/reviewSubmissions',
        'POST /v1/reviewSubmissionItems',
      ]);

      final submitted = await api.submitReviewSubmission(created.id);

      expect(submitted.state, ReviewSubmissionState.waitingForReview);
      expect(submitted.submittedDate, DateTime.utc(2026, 10, 13, 12));
      expect(await api.reviewSubmission(created.id), submitted);
      expect(await api.reviewSubmissions(app.id), [submitted]);
    });

    test('cannot be submitted empty: 409 with the reason', () async {
      final submission = FakeAscSubmission(
        id: 'empty',
        appId: app.id,
        platform: 'IOS',
      );
      server.submissions['empty'] = submission;

      await expectLater(
        client().submitReviewSubmission('empty'),
        throwsA(
          isA<AscConflictException>()
              .having((e) => e.code, 'code', 'ENTITY_ERROR')
              .having(
                (e) => e.message,
                'message',
                contains('Add the app store version'),
              ),
        ),
      );
    });

    test('are 404 for an unknown id', () async {
      await expectLater(
        client().reviewSubmission('nope'),
        throwsA(isA<AscNotFoundException>()),
      );
    });
  });

  group('phased releases', () {
    late FakeAscVersion version;

    setUp(() {
      final app = server.addApp('ly.example.app');
      version = server.addVersion(app.id, '5.4.1');
    });

    test('are read and updated', () async {
      final release = server.addPhasedRelease(
        version.id,
        state: 'ACTIVE',
        currentDayNumber: 4,
      );
      final api = client();

      expect(
        await api.phasedRelease(version.id),
        AscPhasedRelease(
          id: release.id,
          state: PhasedReleaseState.active,
          currentDayNumber: 4,
        ),
      );

      final paused = await api.updatePhasedRelease(
        release.id,
        PhasedReleaseState.paused,
      );

      expect(paused.state, PhasedReleaseState.paused);
      expect(release.state, 'PAUSED');
    });

    test('are null for a version without one', () async {
      expect(await client().phasedRelease(version.id), isNull);
    });

    test('refuse an unknown release: 404', () async {
      await expectLater(
        client().updatePhasedRelease('nope', PhasedReleaseState.complete),
        throwsA(isA<AscNotFoundException>()),
      );
    });
  });

  group('build uploads', () {
    late FakeAscApp app;
    final ipa = utf8.encode('an IPA of 23 bytes, ok.');

    setUp(() {
      app = server.addApp('ly.example.app');
      server.uploadPartSize = 10;
    });

    Future<AscBuildUpload> upload({
      HttpAppStoreConnect? api,
      List<List<int>>? chunks,
      int? length,
    }) => (api ?? client()).uploadBuild(
      app.id,
      version: '5.4.1',
      buildNumber: '3283',
      fileName: 'prod-5.4.1+3283.ipa',
      length: length ?? ipa.length,
      content: () => Stream.fromIterable(
        chunks ?? [ipa.sublist(0, 7), ipa.sublist(7, 12), ipa.sublist(12)],
      ),
    );

    test('send the parts without the token and mark the file', () async {
      final started = await upload();

      expect(started.state, AscBuildUploadState.processing);
      final created = server.buildUploads[started.id]!;
      expect(created.version, '5.4.1');
      expect(created.buildNumber, '3283');
      expect(created.appId, app.id);
      final file = created.file!;
      expect(file.fileName, 'prod-5.4.1+3283.ipa');
      expect(file.fileSize, ipa.length);
      expect(file.bytes, ipa);
      expect(file.uploaded, isTrue);
      final parts = [
        for (final request in server.requests)
          if (request.uri.path.startsWith('/upload/')) request,
      ];
      expect(parts, hasLength(3));
      expect(parts.map((part) => part.method).toSet(), {'PUT'});
      expect(parts.map((part) => part.authorization).toSet(), {null});
      expect(
        server.requests
            .where((request) => request.uri.path.startsWith('/v1/'))
            .map((request) => request.tokenProblem)
            .toSet(),
        {null},
      );
    });

    test('are read until App Store Connect made the build', () async {
      final api = client();
      final started = await upload(api: api);

      final done = await api.buildUpload(started.id);

      expect(done.state, AscBuildUploadState.complete);
      expect(done.buildId, server.builds.single.id);
      expect(server.builds.single.buildNumber, '3283');
      expect(done.errors, isEmpty);
    });

    test('carry the errors of a rejection and the warnings', () async {
      server
        ..uploadPollsBeforeDone = 1
        ..uploadOutcomes.addAll(const [
          FakeAscUploadOutcome.rejected([
            FakeAscIssue('90186', 'The train is closed.'),
          ]),
          FakeAscUploadOutcome.complete(
            warnings: [FakeAscIssue('90683', 'A purpose string is missing.')],
          ),
        ]);

      final rejected = await upload();
      final warned = await upload();

      expect(rejected.state, AscBuildUploadState.failed);
      expect(rejected.errors, const [
        AscUploadIssue(code: '90186', description: 'The train is closed.'),
      ]);
      expect(rejected.buildId, isNull);
      expect(warned.state, AscBuildUploadState.complete);
      expect(warned.warnings, const [
        AscUploadIssue(
          code: '90683',
          description: 'A purpose string is missing.',
        ),
      ]);
    });

    test('of a used build number are a conflict with its code', () async {
      server.addBuild(app.id, buildNumber: '3283', version: '5.4.1');

      await expectLater(
        upload(),
        throwsA(
          isA<AscConflictException>().having(
            (e) => e.code,
            'code',
            'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE',
          ),
        ),
      );
    });

    test('stop when a part is refused', () async {
      server.failNext(500, pathPrefix: '/upload/');

      await expectLater(
        upload(),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            'App Store Connect refused part 1 of the upload (HTTP 500).',
          ),
        ),
      );
      expect(sleeps, isEmpty);
    });

    test('refuse an IPA that is not the size it was said to be', () async {
      await expectLater(
        upload(chunks: [ipa.sublist(0, 12)]),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('not the size'),
          ),
        ),
      );
      await expectLater(
        upload(chunks: [ipa, ipa]),
        throwsA(isA<AscServerException>()),
      );
    });

    test('refuse parts that do not cover the IPA', () async {
      Map<String, Object?> operation(int offset, int length) => {
        'method': 'PUT',
        'url': 'https://upload.example/$offset',
        'offset': offset,
        'length': length,
      };
      for (final (operations, problem) in [
        (<Object?>[], 'do not cover the IPA'),
        ([operation(0, 10), operation(12, 11)], 'do not cover the IPA'),
        ([operation(0, 10)], 'do not cover the IPA'),
        ([operation(0, 10)..['offset'] = '0'], 'no "offset"'),
      ]) {
        final api = client(
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'data': {
                  'type': request.url.path.endsWith('Files')
                      ? 'buildUploadFiles'
                      : 'buildUploads',
                  'id': 'x',
                  'attributes': {'uploadOperations': operations},
                },
              }),
              201,
            ),
          ),
        );

        await expectLater(
          upload(api: api),
          throwsA(
            isA<AscServerException>().having(
              (e) => e.message,
              'message',
              contains(problem),
            ),
          ),
        );
      }
    });

    test('read a state without details as unknown', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'type': 'buildUploads',
                'id': 'u',
                'attributes': {
                  'state': {
                    'state': 'SIDEWAYS',
                    'errors': [
                      {'code': 7},
                    ],
                  },
                },
                'relationships': {'build': 'none'},
              },
            }),
            200,
          ),
        ),
      );

      final read = await api.buildUpload('u');

      expect(read.state, AscBuildUploadState.unknown);
      expect(read.errors, const [AscUploadIssue(code: '', description: '')]);
      expect(read.buildId, isNull);
    });

    test('read an upload without a state as unknown', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {'type': 'buildUploads', 'id': 'u'},
            }),
            200,
          ),
        ),
      );

      expect((await api.buildUpload('u')).state, AscBuildUploadState.unknown);
    });
  });

  group('errors', () {
    Future<Object?> failure(Future<Object?> call) =>
        call.then<Object?>((_) => null, onError: (Object e) => e);

    for (final (status, matcher) in <(int, Matcher)>[
      (403, isA<AscForbiddenException>()),
      (404, isA<AscNotFoundException>()),
      (409, isA<AscConflictException>()),
      (422, isA<AscValidationException>()),
      (400, isA<AscServerException>()),
    ]) {
      test('$status is typed, with the message and code of Apple', () async {
        server.failNext(
          status,
          code: 'SOME_CODE',
          title: 'Title',
          detail: 'Detail of $status.',
        );

        final error = await failure(client().findApp('a.b'));

        expect(error, matcher);
        final exception = error! as AppStoreConnectException;
        expect(exception.statusCode, status);
        expect(exception.message, 'Detail of $status.');
        expect(exception.code, 'SOME_CODE');
        expect(exception.fix, isNotEmpty);
        expect(sleeps, isEmpty);
      });
    }

    test('without a detail fall back to the title', () async {
      server.failNext(403, title: 'Forbidden title');

      final error = await failure(client().findApp('a.b'));

      expect((error! as AppStoreConnectException).message, 'Forbidden title');
    });

    test('a body that is not JSON still gives the status', () async {
      final api = client(
        httpClient: MockClient((_) async => http.Response('<html>', 418)),
      );

      final error = await failure(api.findApp('a.b'));

      expect(error, isA<AscServerException>());
      expect(
        (error! as AppStoreConnectException).message,
        'App Store Connect refused (HTTP 418).',
      );
    });

    test('an error body without errors says it refused', () async {
      final api = client(
        httpClient: MockClient((_) async => http.Response('{}', 400)),
      );

      final error = await failure(api.findApp('a.b'));

      expect(
        (error! as AppStoreConnectException).message,
        'App Store Connect refused.',
      );
      expect((error as AppStoreConnectException).code, isNull);
    });

    test('several errors are joined', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': [
                {'title': 'One', 'code': 'A'},
                {'detail': 'Two'},
                'junk',
              ],
            }),
            422,
          ),
        ),
      );

      final error = await failure(api.findApp('a.b'));

      expect((error! as AppStoreConnectException).message, 'One; Two');
      expect((error as AppStoreConnectException).code, 'A');
    });

    test('an answer that is not a JSON object is a server error', () async {
      final api = client(
        httpClient: MockClient((_) async => http.Response('[1]', 200)),
      );

      final error = await failure(api.findApp('a.b'));

      expect(error, isA<AscServerException>());
      expect(
        (error! as AppStoreConnectException).message,
        contains('not a JSON object'),
      );
    });

    test('an answer without a resource is a server error', () async {
      final api = client(
        httpClient: MockClient((_) async => http.Response('', 204)),
      );

      await expectLater(
        api.reviewSubmission('x'),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('no resource'),
          ),
        ),
      );
    });

    test('an app without a bundle id is a server error', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [
                {'type': 'apps', 'id': '1', 'attributes': <String, Object>{}},
                {'type': 'apps', 'id': '2'},
              ],
            }),
            200,
          ),
        ),
      );

      await expectLater(
        api.findApp('a.b'),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('"bundleId"'),
          ),
        ),
      );
    });

    test('an unknown phased release state is a server error', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'type': 'appStoreVersionPhasedReleases',
                'id': 'p',
                'attributes': {'phasedReleaseState': 'SIDEWAYS'},
              },
            }),
            200,
          ),
        ),
      );

      await expectLater(
        api.phasedRelease('v'),
        throwsA(isA<AscServerException>()),
      );
    });

    test('a missing date or optional field is tolerated', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'type': 'reviewSubmissions',
                'id': 's',
                'attributes': {'submittedDate': 'not a date'},
              },
            }),
            200,
          ),
        ),
      );

      final submission = await api.reviewSubmission('s');

      expect(submission.state, ReviewSubmissionState.unknown);
      expect(submission.platform, 'IOS');
      expect(submission.submittedDate, isNull);
    });

    test('a request that is not answered in time is a server error', () async {
      final never = Completer<http.Response>();
      final api = client(
        httpClient: MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        api.findApp('a.b'),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('did not answer in time'),
          ),
        ),
      );
    });

    test('a connection that fails is a server error', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );

      await expectLater(
        api.findApp('a.b'),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('not reachable'),
          ),
        ),
      );
    });
  });

  group('retries', () {
    test('a 5xx on a read is retried with backoff', () async {
      server
        ..addApp('ly.example.app')
        ..failNext(503, code: 'SERVICE_UNAVAILABLE')
        ..failNext(500);

      final app = await client().findApp('ly.example.app');

      expect(app, isNotNull);
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      expect(server.requests, hasLength(3));
    });

    test('a 5xx on a read is given up on after the attempts', () async {
      server
        ..failNext(500)
        ..failNext(500);

      await expectLater(
        client(maxAttempts: 2).findApp('a.b'),
        throwsA(isA<AscServerException>()),
      );
      expect(server.requests, hasLength(2));
      expect(sleeps, [const Duration(seconds: 1)]);
    });

    test('a 5xx on a write is not retried', () async {
      final app = server.addApp('ly.example.app');
      final version = server.addVersion(app.id, '5.4.1');
      server.failNext(500, pathPrefix: '/v1/reviewSubmissions');

      await expectLater(
        client().createReviewSubmission(app.id, version.id),
        throwsA(isA<AscServerException>()),
      );
      expect(server.requests, hasLength(1));
      expect(sleeps, isEmpty);
    });

    test('a 429 with Retry-After waits that long, then goes on', () async {
      server
        ..addApp('ly.example.app')
        ..rateLimitNext(2, retryAfterSeconds: 3);

      final app = await client().findApp('ly.example.app');

      expect(app, isNotNull);
      expect(sleeps, [const Duration(seconds: 3), const Duration(seconds: 3)]);
    });

    test('a 429 without Retry-After backs off', () async {
      server
        ..addApp('ly.example.app')
        ..rateLimitNext(2);

      await client().findApp('ly.example.app');

      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('a 429 is retried for a write too', () async {
      final app = server.addApp('ly.example.app');
      final version = server.addVersion(app.id, '5.4.1');
      server.rateLimitNext(1, retryAfterSeconds: 1);

      final submission = await client().createReviewSubmission(
        app.id,
        version.id,
      );

      expect(submission.state, ReviewSubmissionState.readyForReview);
    });

    test('a 429 that outlasts the attempts says how long to wait', () async {
      server.rateLimitNext(5, retryAfterSeconds: 4);

      final error = await client(maxAttempts: 2)
          .findApp('a.b')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<AscRateLimitedException>());
      final limited = error! as AscRateLimitedException;
      expect(limited.retryAfter, const Duration(seconds: 4));
      expect(limited.code, 'RATE_LIMIT_EXCEEDED');
      expect(limited.fix, contains('rate limit'));
      expect(sleeps, [const Duration(seconds: 4)]);
    });

    test('a 429 that asks for an hour is not waited out', () async {
      server.rateLimitNext(1, retryAfterSeconds: 3600);

      final error = await client()
          .findApp('a.b')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(
        (error! as AscRateLimitedException).retryAfter,
        const Duration(hours: 1),
      );
      expect(sleeps, isEmpty);
      expect(server.requests, hasLength(1));
    });

    test(
      'a 429 without Retry-After and no attempts left has no wait',
      () async {
        server.rateLimitNext(5);

        final error = await client(maxAttempts: 1)
            .findApp('a.b')
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect((error! as AscRateLimitedException).retryAfter, isNull);
      },
    );
  });

  group('the quota', () {
    test('is read from X-Rate-Limit after each answer', () async {
      server.addApp('ly.example.app');
      final api = client();

      expect(api.rateLimit, isNull);

      await api.findApp('ly.example.app');
      expect(api.rateLimit, const AscRateLimit(limit: 3500, remaining: 3499));

      await api.findApp('ly.example.app');
      expect(api.rateLimit!.remaining, 3498);
    });

    test('keeps the last reading when an answer has none', () async {
      server.addApp('ly.example.app');
      final api = client();
      await api.findApp('ly.example.app');

      server.rateLimitNext(1, retryAfterSeconds: 1);
      await api.findApp('ly.example.app');

      expect(api.rateLimit, isNotNull);
    });
  });

  group('pagination safety', () {
    String page(Uri next) => jsonEncode({
      'data': <Object?>[],
      'links': {'next': next.toString()},
    });

    test('does not follow links.next to another host', () async {
      final api = client(
        httpClient: MockClient(
          (_) async => http.Response(
            page(Uri.parse('https://evil.example/v1/apps?cursor=2')),
            200,
          ),
        ),
        baseUrl: Uri.parse('https://api.appstoreconnect.apple.com'),
      );

      await expectLater(
        api.findApp('a.b'),
        throwsA(
          isA<AscServerException>().having(
            (e) => e.message,
            'message',
            contains('another host, evil.example'),
          ),
        ),
      );
    });

    test('stops a list that never ends', () async {
      final base = Uri.parse('https://api.appstoreconnect.apple.com');
      var calls = 0;
      final api = client(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(page(base.replace(path: '/v1/apps')), 200);
        }),
        baseUrl: base,
      );

      await expectLater(api.findApp('a.b'), throwsA(isA<AscServerException>()));
      expect(calls, 50);
    });
  });

  test('the default base URL is the real API', () async {
    final seen = <Uri>[];
    final api = HttpAppStoreConnect(
      key: _key,
      clock: clock,
      client: MockClient((request) async {
        seen.add(request.url);
        return http.Response('{"data": []}', 200);
      }),
    );

    await api.findApp('a.b');

    expect(seen.single.host, 'api.appstoreconnect.apple.com');
    expect(seen.single.scheme, 'https');
    api.close();
  });

  test('sleeps with Future.delayed by default', () async {
    server
      ..addApp('ly.example.app')
      ..rateLimitNext(1, retryAfterSeconds: 0);
    final api = HttpAppStoreConnect(
      key: _key,
      clock: clock,
      baseUrl: server.baseUrl,
    );
    addTearDown(api.close);

    expect(await api.findApp('ly.example.app'), isNotNull);
  });
}
