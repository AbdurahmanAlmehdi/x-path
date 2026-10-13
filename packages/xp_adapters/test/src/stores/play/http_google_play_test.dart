import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

const _pkg = 'ly.example.app';
const _inReview = 'RELEASE_LIFECYCLE_STATE_IN_REVIEW';

/// A client answering [answer] for the API and a token for `/token`.
MockClient _mock(
  FutureOr<http.Response> Function(http.BaseRequest request) answer,
) => MockClient.streaming((request, body) async {
  if (request.url.path == '/token') {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'access_token': 'ya29.m'}))),
      200,
    );
  }
  final response = await answer(request);
  return http.StreamedResponse(
    Stream.value(response.bodyBytes),
    response.statusCode,
    headers: response.headers,
  );
});

void main() {
  late ManualClock clock;
  late FakePlayServer server;
  late FakePlayApp app;
  late List<Duration> sleeps;

  PlayServiceAccount accountOf(FakePlayServer server) =>
      PlayServiceAccount.fromSecret(server.serviceAccountJson());

  HttpGooglePlay play({
    http.Client? client,
    Uri? apiBaseUrl,
    Uri? uploadBaseUrl,
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 60),
    Duration uploadTimeout = const Duration(minutes: 30),
    PlayServiceAccount? account,
  }) {
    final created = HttpGooglePlay(
      account: account ?? accountOf(server),
      clock: clock,
      client: client,
      apiBaseUrl: apiBaseUrl ?? server.baseUrl,
      uploadBaseUrl: uploadBaseUrl,
      maxAttempts: maxAttempts,
      timeout: timeout,
      uploadTimeout: uploadTimeout,
      sleep: (duration) async => sleeps.add(duration),
    );
    addTearDown(created.close);
    return created;
  }

  Future<Object?> failure(Future<Object?> future) =>
      future.then<Object?>((_) => null, onError: (Object e) => e);

  Stream<List<int>> Function() aab(int versionCode, {int padding = 0}) =>
      () => Stream.fromIterable([fakeAab(versionCode, padding: padding)]);

  int lengthOf(int versionCode, {int padding = 0}) =>
      fakeAab(versionCode, padding: padding).length;

  /// The requests the API (not the token endpoint) received.
  Iterable<FakePlayRequest> api() =>
      server.requests.where((r) => r.uri.path != '/token');

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    sleeps = [];
    server = await FakePlayServer.start(now: clock.now);
    addTearDown(server.close);
    app = server.addApp(_pkg);
  });

  group('the access token', () {
    test('is a valid bearer token on every call', () async {
      final client = play();

      await client.insertEdit(_pkg);
      await client.releases(_pkg, 'internal');

      expect(api().map((r) => r.tokenProblem), [null, null]);
      expect(server.tokensIssued, 1);
    });

    test(
      'is refused with a fix when the key is not the one registered',
      () async {
        final error = await failure(
          play(
            account: PlayServiceAccount.fromSecret(
              server.serviceAccountJson(
                privateKeyPem: fakePlayOtherPrivateKeyPem,
              ),
            ),
          ).insertEdit(_pkg),
        );

        expect(error, isA<PlayAuthException>());
        expect((error! as PlayAuthException).reason, 'invalid_grant');
        expect(api(), isEmpty);
      },
    );

    test('is renewed as time passes', () async {
      final client = play();

      await client.insertEdit(_pkg);
      clock.advance(const Duration(hours: 2));
      await client.insertEdit(_pkg);

      expect(server.tokensIssued, 2);
      expect(api().map((r) => r.tokenProblem), [null, null]);
    });

    test('is replaced once when Google rejects it before it expires', () async {
      final client = play();
      await client.insertEdit(_pkg);

      server.revokeTokens();
      await client.insertEdit(_pkg);

      expect(server.tokensIssued, 2);
      expect(api().map((r) => r.tokenProblem), [null, isNotNull, null]);
    });

    test('is not retried more than once on a 401', () async {
      final client = play();
      server
        ..failNext(401, message: 'no', pathContains: '/edits')
        ..failNext(401, message: 'still no', pathContains: '/edits');

      final error = await failure(client.insertEdit(_pkg));

      expect(error, isA<PlayAuthException>());
      expect((error! as PlayAuthException).message, 'still no');
      expect(api(), hasLength(2));
    });
  });

  group('verifyAccess', () {
    test(
      'exchanges the assertion for a token and calls nothing else',
      () async {
        await play().verifyAccess();

        expect(server.tokensIssued, 1);
        expect(api(), isEmpty);
      },
    );

    test('is refused for a key the server does not know', () async {
      final error = await failure(
        play(
          account: PlayServiceAccount.fromSecret(
            server.serviceAccountJson(
              privateKeyPem: fakePlayOtherPrivateKeyPem,
            ),
          ),
        ).verifyAccess(),
      );

      expect(error, isA<PlayAuthException>());
    });
  });

  group('insertEdit', () {
    test('opens an edit that expires', () async {
      final edit = await play().insertEdit(_pkg);

      expect(edit.id, 'edit-1');
      expect(edit.expiresAt, DateTime.utc(2026, 10, 14, 12));
      expect(
        api().single.uri.path,
        '/androidpublisher/v3/applications/$_pkg/edits',
      );
    });

    test('says an app is not in the Play Console', () async {
      final error = await failure(play().insertEdit('ly.none'));

      expect(error, isA<PlayNotFoundException>());
      final exception = error! as PlayNotFoundException;
      expect(exception.message, 'Package not found: ly.none.');
      expect(exception.reason, 'applicationNotFound');
      expect(exception.fix, contains('Play Console'));
    });

    test('says a service account may not release the app', () async {
      server.addApp('ly.private', allowedAccounts: {'other@x'});

      final error = await failure(play().insertEdit('ly.private'));

      expect(error, isA<PlayForbiddenException>());
      expect(
        (error! as PlayForbiddenException).fix,
        contains('invite the service account'),
      );
    });

    test('is not repeated after a 5xx', () async {
      server.failNext(503, message: 'Backend Error');

      final error = await failure(play().insertEdit(_pkg));

      expect(error, isA<PlayServerException>());
      expect(api(), hasLength(1));
    });

    test('is refused when Play sends no id', () async {
      final client = play(client: _mock((_) => http.Response('{}', 200)));

      expect(
        await failure(client.insertEdit(_pkg)),
        isA<PlayServerException>(),
      );
    });

    test('lives without an expiry', () async {
      final client = play(
        client: _mock((_) => http.Response('{"id": "e1"}', 200)),
      );

      expect(await client.insertEdit(_pkg), const PlayEdit(id: 'e1'));
    });
  });

  group('deleteEdit', () {
    test('throws the edit away', () async {
      final client = play();
      final edit = await client.insertEdit(_pkg);

      await client.deleteEdit(_pkg, edit.id);

      expect(server.edits[edit.id]!.deleted, isTrue);
    });

    test('is repeated after a 5xx', () async {
      final client = play();
      final edit = await client.insertEdit(_pkg);
      server.failNext(503, method: 'DELETE');

      await client.deleteEdit(_pkg, edit.id);

      expect(sleeps, [const Duration(seconds: 1)]);
      expect(server.edits[edit.id]!.deleted, isTrue);
    });

    test('says an edit is gone', () async {
      final error = await failure(play().deleteEdit(_pkg, 'edit-99'));

      expect((error! as PlayNotFoundException).reason, 'editNotFound');
    });
  });

  group('uploadBundle', () {
    late HttpGooglePlay client;
    late String editId;

    setUp(() async {
      client = play();
      editId = (await client.insertEdit(_pkg)).id;
    });

    test('streams the bundle with its length', () async {
      final bundle = await client.uploadBundle(
        _pkg,
        editId,
        content: aab(3283, padding: 5000),
        length: lengthOf(3283, padding: 5000),
      );

      expect(bundle.versionCode, 3283);
      expect(bundle.sha256, hasLength(64));
      final request = api().last;
      expect(request.method, 'POST');
      expect(
        request.uri.path,
        '/upload/androidpublisher/v3/applications/$_pkg/edits/$editId/bundles',
      );
      expect(request.uri.queryParameters, {'uploadType': 'media'});
      expect(request.contentType, 'application/octet-stream');
      expect(request.bodyLength, lengthOf(3283, padding: 5000));
      expect(server.edits[editId]!.bundles.keys, [3283]);
    });

    test('goes to the upload host', () async {
      final seen = <Uri>[];
      final client = play(
        apiBaseUrl: Uri.parse('https://api.example.com'),
        uploadBaseUrl: Uri.parse('https://upload.example.com'),
        client: _mock((request) {
          seen.add(request.url);
          return http.Response('{"versionCode": 7}', 200);
        }),
      );

      await client.uploadBundle(
        _pkg,
        'e1',
        content: aab(7),
        length: lengthOf(7),
      );
      await client.bundles(_pkg, 'e1');

      expect(seen.map((u) => u.host), [
        'upload.example.com',
        'api.example.com',
      ]);
    });

    test('uploads to the API host unless told otherwise', () async {
      final seen = <Uri>[];
      final client = play(
        apiBaseUrl: Uri.parse('https://api.example.com'),
        client: _mock((request) {
          seen.add(request.url);
          return http.Response('{"versionCode": 7}', 200);
        }),
      );

      await client.uploadBundle(_pkg, 'e1', content: aab(7), length: 1);

      expect(seen.single.host, 'api.example.com');
    });

    test('opens the bundle again when the upload is repeated', () async {
      var opened = 0;
      server.rateLimitNext(1, retryAfterSeconds: 2);

      final bundle = await client.uploadBundle(
        _pkg,
        editId,
        content: () {
          opened++;
          return aab(5)();
        },
        length: lengthOf(5),
      );

      expect(bundle.versionCode, 5);
      expect(opened, 2);
      expect(sleeps, [const Duration(seconds: 2)]);
    });

    test('is not repeated after a 5xx, which may have gone through', () async {
      var opened = 0;
      server.failNext(503, method: 'POST', pathContains: '/bundles');

      final error = await failure(
        client.uploadBundle(
          _pkg,
          editId,
          content: () {
            opened++;
            return aab(5)();
          },
          length: lengthOf(5),
        ),
      );

      expect(error, isA<PlayServerException>());
      expect(opened, 1);
      expect(sleeps, isEmpty);
    });

    test('says a version code was used', () async {
      app.addRelease('production', [3283]);

      final error = await failure(
        client.uploadBundle(
          _pkg,
          editId,
          content: aab(3283),
          length: lengthOf(3283),
        ),
      );

      expect(error, isA<PlayVersionCodeUsedException>());
      final exception = error! as PlayVersionCodeUsedException;
      expect(exception.statusCode, 403);
      expect(exception.reason, 'apkUpgradeVersionConflict');
      expect(exception.fix, contains('new build number'));
    });

    test('says a bundle is not an Android App Bundle', () async {
      final error = await failure(
        client.uploadBundle(
          _pkg,
          editId,
          content: () => Stream.value([1, 2, 3]),
          length: 3,
        ),
      );

      expect(error, isA<PlayValidationException>());
      expect(
        (error! as PlayValidationException).message,
        contains('not a valid Android App'),
      );
    });

    test('fails with the reason when the bundle cannot be read', () async {
      final error = await failure(
        client.uploadBundle(
          _pkg,
          editId,
          content: () => Stream.error(StateError('disk gone')),
          length: 100,
        ),
      );

      expect(error, isNotNull);
    });

    test('has its own, longer time limit', () async {
      final slow = play(
        timeout: const Duration(milliseconds: 1),
        client: _mock((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{"versionCode": 1}', 200);
        }),
      );

      expect(
        await slow.uploadBundle(_pkg, 'e1', content: aab(1), length: 1),
        const PlayBundle(versionCode: 1),
      );
      await expectLater(
        slow.bundles(_pkg, 'e1'),
        throwsA(isA<PlayServerException>()),
      );
    });

    test('is refused when Play sends no version code', () async {
      final client = play(client: _mock((_) => http.Response('{}', 200)));

      expect(
        await failure(
          client.uploadBundle(_pkg, 'e', content: aab(1), length: 1),
        ),
        isA<PlayServerException>(),
      );
    });
  });

  group('bundles', () {
    test('lists the bundles of the app and of the edit', () async {
      app.addRelease('production', [3000]);
      final client = play();
      final edit = await client.insertEdit(_pkg);
      await client.uploadBundle(
        _pkg,
        edit.id,
        content: aab(3001),
        length: lengthOf(3001),
      );

      final bundles = await client.bundles(_pkg, edit.id);

      expect(bundles.map((b) => b.versionCode), [3000, 3001]);
    });

    test('are empty for an app without any', () async {
      final client = play();
      final edit = await client.insertEdit(_pkg);

      expect(await client.bundles(_pkg, edit.id), isEmpty);
    });

    test('are read again after a 5xx', () async {
      final client = play();
      final edit = await client.insertEdit(_pkg);
      server.failNext(500, method: 'GET');

      await client.bundles(_pkg, edit.id);

      expect(sleeps, [const Duration(seconds: 1)]);
    });
  });

  group('tracks', () {
    late HttpGooglePlay client;
    late String editId;

    setUp(() async {
      client = play();
      editId = (await client.insertEdit(_pkg)).id;
      await client.uploadBundle(
        _pkg,
        editId,
        content: aab(3283),
        length: lengthOf(3283),
      );
    });

    test('take a staged release with its name and notes', () async {
      const track = PlayTrack(
        name: 'production',
        releases: [
          PlayRelease(
            versionCodes: [3283],
            status: PlayReleaseStatus.inProgress,
            userFraction: 0.1,
            name: '5.4.1',
            releaseNotes: {'en-US': 'Fixes', 'ar': 'Fixes in Arabic'},
          ),
        ],
      );

      final updated = await client.updateTrack(_pkg, editId, track);

      expect(updated, track);
      expect(await client.track(_pkg, editId, 'production'), track);
      final body = api().firstWhere((r) => r.method == 'PUT').body! as Map;
      expect(body['track'], 'production');
      expect((body['releases'] as List).single, {
        'versionCodes': ['3283'],
        'status': 'inProgress',
        'userFraction': 0.1,
        'name': '5.4.1',
        'releaseNotes': [
          {'language': 'en-US', 'text': 'Fixes'},
          {'language': 'ar', 'text': 'Fixes in Arabic'},
        ],
      });
    });

    test('send only what the release has', () async {
      await client.updateTrack(
        _pkg,
        editId,
        const PlayTrack(
          name: 'internal',
          releases: [
            PlayRelease(
              versionCodes: [3283],
              status: PlayReleaseStatus.completed,
            ),
          ],
        ),
      );

      final body = api().firstWhere((r) => r.method == 'PUT').body! as Map;
      expect((body['releases'] as List).single, {
        'versionCodes': ['3283'],
        'status': 'completed',
      });
    });

    test('are empty before anything is released', () async {
      final track = await client.track(_pkg, editId, 'beta');

      expect(track, const PlayTrack(name: 'beta'));
    });

    test('refuse a version code that was not uploaded', () async {
      final error = await failure(
        client.updateTrack(
          _pkg,
          editId,
          const PlayTrack(
            name: 'internal',
            releases: [
              PlayRelease(
                versionCodes: [1],
                status: PlayReleaseStatus.completed,
              ),
            ],
          ),
        ),
      );

      expect(error, isA<PlayValidationException>());
      expect(
        (error! as PlayValidationException).message,
        'Version code 1 has not been uploaded.',
      );
    });

    test('are written with the track name encoded', () async {
      final seen = <Uri>[];
      final client = play(
        client: _mock((request) {
          seen.add(request.url);
          return http.Response('{}', 200);
        }),
      );

      await client.track(_pkg, 'e1', 'wear:production');

      expect(seen.single.path, endsWith('/tracks/wear%3Aproduction'));
    });

    test('tolerate answers that leave things out', () async {
      final client = play(
        client: _mock(
          (_) => http.Response(
            jsonEncode({
              'releases': [
                {
                  'versionCodes': [3, '4', 'x'],
                  'status': 'nonsense',
                  'releaseNotes': [
                    {'language': 'en-US'},
                    {'text': 'no language'},
                  ],
                },
                'not a release',
              ],
            }),
            200,
          ),
        ),
      );

      final track = await client.track(_pkg, 'e1', 'internal');

      expect(
        track,
        const PlayTrack(
          name: 'internal',
          releases: [
            PlayRelease(
              versionCodes: [3, 4],
              status: PlayReleaseStatus.unknown,
              releaseNotes: {'en-US': ''},
            ),
          ],
        ),
      );
    });
  });

  group('commitEdit', () {
    late HttpGooglePlay client;
    late String editId;

    setUp(() async {
      client = play();
      editId = (await client.insertEdit(_pkg)).id;
      await client.uploadBundle(
        _pkg,
        editId,
        content: aab(3283),
        length: lengthOf(3283),
      );
      await client.updateTrack(
        _pkg,
        editId,
        const PlayTrack(
          name: 'internal',
          releases: [
            PlayRelease(
              versionCodes: [3283],
              status: PlayReleaseStatus.completed,
            ),
          ],
        ),
      );
    });

    test('publishes the release and sends ERROR_IF_IN_REVIEW', () async {
      await client.commitEdit(_pkg, editId);

      expect(app.bundles.keys, [3283]);
      expect(server.commits.single.editId, editId);
      expect(
        server.commits.single.changesInReviewBehavior,
        'ERROR_IF_IN_REVIEW',
      );
      final request = api().last;
      expect(request.method, 'POST');
      expect(
        request.uri.path,
        '/androidpublisher/v3/applications/$_pkg/edits/$editId:commit',
      );
      expect(request.uri.queryParameters, {
        'changesInReviewBehavior': 'ERROR_IF_IN_REVIEW',
      });
    });

    // The acceptance criterion of Phase 10b.
    test('while a review is in progress fails without cancelling it', () async {
      app.addRelease(
        'production',
        [3200],
        lifecycleState: _inReview,
        name: 'under review',
      );

      final error = await failure(client.commitEdit(_pkg, editId));

      expect(error, isA<PlayReviewInProgressException>());
      final exception = error! as PlayReviewInProgressException;
      expect(exception.reason, 'CHANGES_ALREADY_IN_REVIEW');
      expect(exception.statusCode, 400);
      expect(exception.message, contains('changes in review'));
      expect(exception.fix, contains('Wait for the review'));
      // The fake server saw the parameter; the review is untouched.
      expect(
        server.commits.single.changesInReviewBehavior,
        'ERROR_IF_IN_REVIEW',
      );
      expect(server.commits.single.cancelledReview, isFalse);
      expect(app.cancelledReviews, isEmpty);
      expect(app.reviewInProgress, isTrue);
      expect(app.tracks['production']!.single.lifecycleState, _inReview);
      expect(app.tracks.containsKey('internal'), isFalse);
      expect(sleeps, isEmpty);
      // The edit is still valid, as Google documents.
      expect(server.edits[editId]!.committed, isFalse);
      await client.deleteEdit(_pkg, editId);
    });

    test('is not repeated after a 5xx, which may have gone through', () async {
      server.failNext(503, pathContains: ':commit');

      final error = await failure(client.commitEdit(_pkg, editId));

      expect(error, isA<PlayServerException>());
      expect(server.commits, isEmpty);
      expect(sleeps, isEmpty);
    });

    test('says an edit conflicts with a change made elsewhere', () async {
      server.failNext(
        409,
        message: 'The edit is no longer valid.',
        pathContains: ':commit',
      );

      final error = await failure(client.commitEdit(_pkg, editId));

      expect(error, isA<PlayConflictException>());
      expect((error! as PlayConflictException).fix, contains('Play Console'));
    });
  });

  group('releases', () {
    test('lists the review state and the version codes of a track', () async {
      app
        ..addRelease(
          'production',
          [3200],
          lifecycleState: _inReview,
          name: '5.4.0',
        )
        ..addRelease('production', [3100, 3101]);

      final releases = await play().releases(_pkg, 'production');

      expect(releases, [
        const PlayReleaseSummary(
          track: 'production',
          name: '5.4.0',
          state: PlayLifecycleState.inReview,
          versionCodes: [3200],
        ),
        const PlayReleaseSummary(
          track: 'production',
          state: PlayLifecycleState.published,
          versionCodes: [3100, 3101],
        ),
      ]);
      expect(
        api().last.uri.path,
        '/androidpublisher/v3/applications/$_pkg/tracks/production/releases',
      );
    });

    test('is empty for a track without releases', () async {
      expect(await play().releases(_pkg, 'beta'), isEmpty);
    });

    test('names a state it does not know unknown', () async {
      final client = play(
        client: _mock(
          (_) => http.Response(
            jsonEncode({
              'releases': [
                {'releaseLifecycleState': 'SOMETHING_NEW'},
                {'releaseLifecycleState': 'RELEASE_LIFECYCLE_STATE_DRAFT'},
              ],
            }),
            200,
          ),
        ),
      );

      final releases = await client.releases(_pkg, 'internal');

      expect(releases.map((r) => r.state), [
        PlayLifecycleState.unknown,
        PlayLifecycleState.draft,
      ]);
      expect(releases.first.track, 'internal');
    });

    test('encodes the application id and the track', () async {
      final seen = <Uri>[];
      final client = play(
        client: _mock((request) {
          seen.add(request.url);
          return http.Response('{}', 200);
        }),
      );

      await client.releases('a/b', 'x y');

      expect(
        seen.single.path,
        '/androidpublisher/v3/applications/a%2Fb/tracks/x%20y/releases',
      );
    });
  });

  group('rate limits and server errors', () {
    test('a 429 is waited out as Google says', () async {
      server.rateLimitNext(1, retryAfterSeconds: 3);

      await play().releases(_pkg, 'internal');

      expect(sleeps, [const Duration(seconds: 3)]);
    });

    test('a 429 without Retry-After backs off 1 s, 2 s, ...', () async {
      server.rateLimitNext(2);

      await play().releases(_pkg, 'internal');

      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('gives up after the attempts and says how long to wait', () async {
      server.rateLimitNext(5, retryAfterSeconds: 4);

      final error = await failure(play().releases(_pkg, 'internal'));

      expect(error, isA<PlayRateLimitedException>());
      expect(
        (error! as PlayRateLimitedException).retryAfter,
        const Duration(seconds: 4),
      );
      expect(sleeps, hasLength(2));
    });

    test('does not sleep through a long wait', () async {
      server.rateLimitNext(1, retryAfterSeconds: 600);

      final error = await failure(play().releases(_pkg, 'internal'));

      expect(
        (error! as PlayRateLimitedException).retryAfter,
        const Duration(minutes: 10),
      );
      expect(sleeps, isEmpty);
    });

    test('a 5xx on a read is retried, then thrown', () async {
      server
        ..failNext(500, method: 'GET')
        ..failNext(502, method: 'GET')
        ..failNext(503, method: 'GET');

      final error = await failure(play().releases(_pkg, 'internal'));

      expect(error, isA<PlayServerException>());
      expect((error! as PlayServerException).statusCode, 503);
      expect(sleeps, hasLength(2));
    });
  });

  group('errors', () {
    test('without a Google error body still say what happened', () async {
      final client = play(
        client: _mock((_) => http.Response('<html>bad gateway</html>', 502)),
        maxAttempts: 1,
      );

      final error = await failure(client.releases(_pkg, 'internal'));

      expect(error, isA<PlayServerException>());
      expect(
        (error! as PlayServerException).message,
        'Google Play refused (HTTP 502).',
      );
    });

    test('with an error object without a message', () async {
      final client = play(
        client: _mock((_) => http.Response('{"error": {}}', 400)),
      );

      final error = await failure(client.releases(_pkg, 'internal'));

      expect(error, isA<PlayValidationException>());
      expect(
        (error! as PlayValidationException).message,
        'Google Play refused.',
      );
    });

    test('take the reason of the ErrorInfo before that of errors', () async {
      final client = play(
        client: _mock(
          (_) => http.Response(
            jsonEncode({
              'error': {
                'message': 'm',
                'errors': [
                  {'reason': 'first'},
                ],
                'details': [
                  {'@type': 'other'},
                  {'reason': 'info'},
                ],
              },
            }),
            400,
          ),
        ),
      );

      final error = await failure(client.releases(_pkg, 'internal'));

      expect((error! as PlayException).reason, 'info');
    });

    test('take the version code text of an error without a reason', () async {
      final client = play(
        client: _mock(
          (_) => http.Response(
            jsonEncode({
              'error': {
                'message':
                    'APK specifies a version code that has already been used.',
              },
            }),
            403,
          ),
        ),
      );

      expect(
        await failure(client.releases(_pkg, 'internal')),
        isA<PlayVersionCodeUsedException>(),
      );
    });

    test('also know the bundle version conflict reason', () async {
      final client = play(
        client: _mock(
          (_) => http.Response(
            jsonEncode({
              'error': {
                'message': 'Conflict',
                'errors': [
                  {'reason': 'bundleVersionConflict'},
                ],
              },
            }),
            400,
          ),
        ),
      );

      expect(
        await failure(client.releases(_pkg, 'internal')),
        isA<PlayVersionCodeUsedException>(),
      );
    });

    test('a success that is not JSON is a server problem', () async {
      final client = play(client: _mock((_) => http.Response('[1]', 200)));

      expect(
        await failure(client.bundles(_pkg, 'e1')),
        isA<PlayServerException>(),
      );
    });

    test('a success without a body is an empty answer', () async {
      final client = play(client: _mock((_) => http.Response('', 200)));

      expect(await client.bundles(_pkg, 'e1'), isEmpty);
    });

    test('a server that is not reachable', () async {
      final client = play(
        client: _mock((_) => throw http.ClientException('connection refused')),
      );

      final error = await failure(client.releases(_pkg, 'internal'));

      expect(error, isA<PlayServerException>());
      expect(
        (error! as PlayServerException).message,
        contains('connection refused'),
      );
    });

    test('a server that does not answer in time', () async {
      final client = play(
        timeout: const Duration(milliseconds: 20),
        client: _mock((_) => Completer<http.Response>().future),
      );

      final error = await failure(client.releases(_pkg, 'internal'));

      expect((error! as PlayServerException).message, contains('in time'));
    });
  });

  test('uses the real Google hosts unless told otherwise', () async {
    final seen = <Uri>[];
    final client = HttpGooglePlay(
      account: accountOf(server),
      clock: clock,
      client: _mock((request) {
        seen.add(request.url);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    // The token endpoint of the account is the fake's; the API is Google's.
    await client.releases(_pkg, 'internal');

    expect(seen.single.host, 'androidpublisher.googleapis.com');
    expect(seen.single.scheme, 'https');
  });
}
