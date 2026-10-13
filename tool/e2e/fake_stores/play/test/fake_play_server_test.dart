import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

import 'helpers/mint.dart';

const _pkg = 'ly.example.app';
const _api = '/androidpublisher/v3/applications/$_pkg';
const _inReview = 'RELEASE_LIFECYCLE_STATE_IN_REVIEW';

void main() {
  late FakePlayServer server;
  late http.Client client;
  late DateTime now;
  late String token;
  late FakePlayApp app;

  Future<http.Response> exchange(
    String assertion, {
    String grantType = 'urn:ietf:params:oauth:grant-type:jwt-bearer',
  }) => client.post(
    server.tokenUri,
    body: {'grant_type': grantType, 'assertion': assertion},
  );

  Future<String> token0() async {
    final response = await exchange(mint(server.tokenUri));
    return (jsonDecode(response.body) as Map<String, dynamic>)['access_token']
        as String;
  }

  setUp(() async {
    now = testNow;
    server = await FakePlayServer.start(
      now: () => now,
      editLifetime: const Duration(minutes: 30),
    );
    client = http.Client();
    addTearDown(() async {
      client.close();
      await server.close();
    });
    app = server.addApp(_pkg);
    token = await token0();
  });

  Future<http.Response> post(
    String path, {
    Object? body,
    String? bearer,
    Map<String, String>? query,
    Map<String, String>? headers,
    List<int>? bytes,
    String method = 'POST',
    bool anonymous = false,
  }) async {
    final request = http.Request(
      method,
      server.baseUrl.replace(path: path, queryParameters: query),
    );
    if (!anonymous) {
      request.headers['Authorization'] = 'Bearer ${bearer ?? token}';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (bytes != null) {
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    }
    request.headers.addAll(headers ?? const {});
    return await http.Response.fromStream(await client.send(request));
  }

  Future<http.Response> get(String path, {String? bearer}) =>
      post(path, method: 'GET', bearer: bearer);

  Map<String, dynamic> json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  Map<String, dynamic> error(http.Response response) =>
      json(response)['error'] as Map<String, dynamic>;

  Future<String> insertEdit() async =>
      json(await post('$_api/edits'))['id'] as String;

  Future<http.Response> upload(
    String editId,
    int versionCode, {
    Map<String, String> query = const {'uploadType': 'media'},
  }) => post(
    '/upload$_api/edits/$editId/bundles',
    bytes: fakeAab(versionCode, padding: 100),
    query: query,
  );

  Future<http.Response> setTrack(
    String editId,
    String track,
    List<Map<String, Object?>> releases,
  ) => post(
    '$_api/edits/$editId/tracks/$track',
    method: 'PUT',
    body: {'track': track, 'releases': releases},
  );

  Map<String, Object?> release(
    List<int> codes, {
    String status = 'completed',
    double? fraction,
  }) => {
    'versionCodes': [for (final code in codes) '$code'],
    'status': status,
    'userFraction': ?fraction,
  };

  Future<http.Response> commit(String editId, {String? behavior}) => post(
    '$_api/edits/$editId:commit',
    query: {'changesInReviewBehavior': ?behavior},
  );

  group('the token endpoint', () {
    test('exchanges a valid assertion for a bearer token', () async {
      final response = await exchange(mint(server.tokenUri));

      expect(response.statusCode, 200);
      expect(json(response)['token_type'], 'Bearer');
      expect(json(response)['expires_in'], 3600);
      expect(server.tokensIssued, 2);
    });

    test('refuses a bad assertion and says why', () async {
      final response = await exchange(mint(server.tokenUri, tamper: true));

      expect(response.statusCode, 400);
      expect(json(response), {
        'error': 'invalid_grant',
        'error_description': 'Invalid JWT Signature.',
      });
    });

    test('refuses another grant type and a missing assertion', () async {
      final grant = await exchange('x', grantType: 'password');
      expect(json(grant)['error'], 'unsupported_grant_type');

      final missing = await client.post(
        server.tokenUri,
        body: {'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer'},
      );
      expect(json(missing)['error'], 'invalid_request');
    });

    test('hands out the service account JSON that points at it', () {
      final account = jsonDecode(server.serviceAccountJson()) as Map;

      expect(account['token_uri'], '${server.tokenUri}');
      expect(account['client_email'], fakePlayClientEmail);
      expect(account['type'], 'service_account');
    });
  });

  test('judges time by the system clock unless given another', () async {
    final real = await FakePlayServer.start();
    addTearDown(real.close);

    final response = await client.post(
      real.tokenUri,
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        // Minted long ago by any clock.
        'assertion': mint(real.tokenUri, claims: {'iat': 1, 'exp': 100}),
      },
    );

    expect(json(response)['error_description'], contains('has expired'));
  });

  group('the access token', () {
    test('is required, valid and not expired', () async {
      final anonymous = await post('$_api/edits', anonymous: true);
      expect(anonymous.statusCode, 401);
      expect(error(anonymous)['status'], 'UNAUTHENTICATED');

      final unknown = await post('$_api/edits', bearer: 'ya29.nope');
      expect(unknown.statusCode, 401);
      expect(server.requests.last.tokenProblem, isNotNull);

      now = now.add(const Duration(hours: 2));
      final expired = await post('$_api/edits');
      expect(expired.statusCode, 401);
      expect(error(expired)['message'], contains('expired'));
    });

    test('is refused after revokeTokens', () async {
      server.revokeTokens();

      expect((await post('$_api/edits')).statusCode, 401);
    });
  });

  group('edits', () {
    test('open, expire and are deleted', () async {
      final response = await post('$_api/edits');
      final id = json(response)['id'] as String;
      expect(response.statusCode, 200);
      final expires = now.add(const Duration(minutes: 30));
      expect(
        json(response)['expiryTimeSeconds'],
        '${expires.millisecondsSinceEpoch ~/ 1000}',
      );

      final deleted = await post('$_api/edits/$id', method: 'DELETE');
      expect(deleted.statusCode, 204);
      expect(server.edits[id]!.deleted, isTrue);

      final again = await post('$_api/edits/$id', method: 'DELETE');
      expect(again.statusCode, 404);
      expect(
        (error(again)['errors'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .first['reason'],
        'editNotFound',
      );
    });

    test('are gone after their lifetime', () async {
      final id = await insertEdit();
      now = now.add(const Duration(minutes: 40));

      expect((await get('$_api/edits/$id/bundles')).statusCode, 404);
    });

    test('belong to their app', () async {
      server.addApp('ly.other');
      final id = await insertEdit();

      final response = await get(
        '/androidpublisher/v3/applications/ly.other/edits/$id/bundles',
      );

      expect(response.statusCode, 404);
    });

    test('are not offered for an app the server does not have', () async {
      final response = await post(
        '/androidpublisher/v3/applications/ly.none/edits',
      );

      expect(response.statusCode, 404);
      expect(error(response)['message'], 'Package not found: ly.none.');
    });

    test('are refused to an account that may not release the app', () async {
      server.addApp('ly.private', allowedAccounts: {'other@x'});

      final response = await post(
        '/androidpublisher/v3/applications/ly.private/edits',
      );

      expect(response.statusCode, 403);
      expect(error(response)['status'], 'PERMISSION_DENIED');
    });

    test('know only their API paths', () async {
      expect((await get('/other/v3/applications/$_pkg/edits')).statusCode, 404);
      expect((await get('$_api/nothing')).statusCode, 404);
      final id = await insertEdit();
      expect((await post('$_api/edits/$id:publish')).statusCode, 404);
    });
  });

  group('bundles', () {
    test('are uploaded by media upload and listed with the edit', () async {
      final id = await insertEdit();

      final response = await upload(id, 3283);

      expect(response.statusCode, 200);
      expect(json(response)['versionCode'], 3283);
      expect(json(response)['sha256'], hasLength(64));
      expect(json(response)['sha1'], hasLength(40));
      final request = server.requests.last;
      expect(request.contentType, 'application/octet-stream');
      expect(request.bodyLength, fakeAab(3283, padding: 100).length);

      app.addRelease('production', [3000]);
      final list = await get('$_api/edits/$id/bundles');
      expect(
        [
          for (final bundle in json(list)['bundles'] as List<dynamic>)
            (bundle as Map)['versionCode'],
        ],
        [3000, 3283],
      );
    });

    test('are refused when they are not an AAB', () async {
      final id = await insertEdit();

      final response = await post(
        '/upload$_api/edits/$id/bundles',
        bytes: utf8.encode('hello'),
        query: {'uploadType': 'media'},
      );

      expect(response.statusCode, 400);
      expect(error(response)['message'], contains('not a valid Android App'));
    });

    test('are refused for other upload types', () async {
      final id = await insertEdit();

      final response = await upload(id, 1, query: {'uploadType': 'resumable'});

      expect(response.statusCode, 400);
    });

    test('are refused when the version code was used', () async {
      app.addRelease('production', [3283]);
      final id = await insertEdit();

      final response = await upload(id, 3283);

      expect(response.statusCode, 403);
      expect(error(response)['message'], contains('already been used'));

      await upload(id, 3284);
      expect((await upload(id, 3284)).statusCode, 403);
    });
  });

  group('tracks', () {
    late String id;

    setUp(() async {
      id = await insertEdit();
      await upload(id, 3283);
    });

    test('take a release of an uploaded bundle', () async {
      final response = await setTrack(id, 'internal', [
        {
          ...release([3283]),
          'name': '5.4.1',
          'releaseNotes': [
            {'language': 'en-US', 'text': 'Fixes'},
          ],
        },
      ]);

      expect(response.statusCode, 200);
      final read = json(await get('$_api/edits/$id/tracks/internal'));
      expect(read['track'], 'internal');
      final releases = read['releases'] as List<dynamic>;
      expect((releases.single as Map)['versionCodes'], ['3283']);
      expect((releases.single as Map)['name'], '5.4.1');
      expect((releases.single as Map)['releaseNotes'], hasLength(1));
    });

    test('show the committed releases before the edit changes them', () async {
      app.addRelease('production', [3000], name: 'old');

      final read = json(await get('$_api/edits/$id/tracks/production'));

      expect(((read['releases'] as List).single as Map)['name'], 'old');
      expect(
        json(await get('$_api/edits/$id/tracks/beta'))['releases'],
        isEmpty,
      );
    });

    test('refuse what Play refuses', () async {
      Future<String> message(List<Map<String, Object?>> releases) async {
        final response = await setTrack(id, 'internal', releases);
        expect(response.statusCode, 400);
        return error(response)['message'] as String;
      }

      expect(
        await message([
          release([9999]),
        ]),
        'Version code 9999 has not been uploaded.',
      );
      expect(await message([release([])]), contains('at least one'));
      expect(
        await message([
          release([3283], status: 'live'),
        ]),
        contains('Invalid release status'),
      );
      expect(
        await message([
          release([3283], status: 'inProgress'),
        ]),
        contains('needs a userFraction'),
      );
      expect(
        await message([
          release([3283], fraction: 0.5),
        ]),
        contains('cannot have a userFraction'),
      );
    });

    test('accept a staged rollout and a draft', () async {
      expect(
        (await setTrack(id, 'production', [
          release([3283], status: 'inProgress', fraction: 0.1),
        ])).statusCode,
        200,
      );
      expect(
        (await setTrack(id, 'beta', [
          release([3283], status: 'draft'),
        ])).statusCode,
        200,
      );
    });

    test('must be the track of the path, and a JSON object', () async {
      final other = await post(
        '$_api/edits/$id/tracks/internal',
        method: 'PUT',
        body: {'track': 'beta', 'releases': <Object>[]},
      );
      expect(other.statusCode, 400);

      final text = await post(
        '$_api/edits/$id/tracks/internal',
        method: 'PUT',
        body: [1],
      );
      expect(text.statusCode, 400);
    });
  });

  group('commit', () {
    late String id;

    setUp(() async {
      id = await insertEdit();
      await upload(id, 3283);
      await setTrack(id, 'internal', [
        release([3283]),
      ]);
    });

    test('publishes the bundle and the release', () async {
      final response = await commit(id, behavior: 'ERROR_IF_IN_REVIEW');

      expect(response.statusCode, 200);
      expect(app.bundles.keys, [3283]);
      expect(
        app.tracks['internal']!.single.lifecycleState,
        'RELEASE_LIFECYCLE_STATE_PUBLISHED',
      );
      expect(
        server.commits.single.changesInReviewBehavior,
        'ERROR_IF_IN_REVIEW',
      );
      expect(server.commits.single.status, 200);
      expect(server.commits.single.cancelledReview, isFalse);
      // A committed edit cannot be used again.
      expect((await commit(id)).statusCode, 404);
    });

    test('puts a draft in the draft state and can go to review', () async {
      await setTrack(id, 'beta', [
        release([3283], status: 'draft'),
      ]);
      server.sendsToReview = true;

      await commit(id);

      expect(app.tracks['beta']!.single.lifecycleState, contains('DRAFT'));
      expect(app.tracks['internal']!.single.lifecycleState, _inReview);
    });

    group('while a review is in progress', () {
      setUp(() {
        app.addRelease(
          'production',
          [3200],
          lifecycleState: _inReview,
          name: 'under review',
        );
      });

      test(
        'with ERROR_IF_IN_REVIEW fails, keeps the edit and the review',
        () async {
          final response = await commit(id, behavior: 'ERROR_IF_IN_REVIEW');

          expect(response.statusCode, 400);
          expect(error(response)['status'], 'FAILED_PRECONDITION');
          final details = (error(response)['details'] as List).single as Map;
          expect(details['reason'], 'CHANGES_ALREADY_IN_REVIEW');
          expect(details['metadata'], containsPair('editId', id));
          expect(app.reviewInProgress, isTrue);
          expect(app.cancelledReviews, isEmpty);
          expect(app.bundles.keys, [3200]);
          expect(server.edits[id]!.committed, isFalse);
          expect(
            server.commits.single.changesInReviewBehavior,
            'ERROR_IF_IN_REVIEW',
          );
          // The edit is still valid: the same edit commits once the review
          // is over.
          app.tracks['production']!.single.lifecycleState =
              'RELEASE_LIFECYCLE_STATE_PUBLISHED';
          expect(
            (await commit(id, behavior: 'ERROR_IF_IN_REVIEW')).statusCode,
            200,
          );
        },
      );

      test('without the parameter cancels the review', () async {
        final response = await commit(id);

        expect(response.statusCode, 200);
        expect(app.cancelledReviews, ['under review']);
        expect(app.reviewInProgress, isFalse);
        expect(server.commits.single.changesInReviewBehavior, isNull);
        expect(server.commits.single.cancelledReview, isTrue);
        expect(
          app.tracks['production']!.single.lifecycleState,
          contains('NOT_SENT_FOR_REVIEW'),
        );
      });

      test('with CANCEL_IN_REVIEW_AND_SUBMIT cancels the review', () async {
        await commit(id, behavior: 'CANCEL_IN_REVIEW_AND_SUBMIT');

        expect(app.cancelledReviews, ['under review']);
      });

      test('names an unnamed release by its version codes', () async {
        app.tracks['production']!.single.name = null;

        await commit(id);

        expect(app.cancelledReviews, ['[3200]']);
      });
    });
  });

  group('tracks.releases.list', () {
    test('lists the committed releases with their review state', () async {
      app
        ..addRelease('production', [3200], lifecycleState: _inReview, name: 'a')
        ..addRelease('production', [3100, 3101]);

      final response = await get('$_api/tracks/production/releases');

      expect(response.statusCode, 200);
      final releases = (json(response)['releases'] as List)
          .cast<Map<String, dynamic>>();
      expect(releases.first['releaseLifecycleState'], _inReview);
      expect(releases.first['releaseName'], 'a');
      expect(releases.first['track'], 'production');
      expect(releases.first['activeArtifacts'], [
        {'versionCode': 3200},
      ]);
      expect(releases.last.containsKey('releaseName'), isFalse);
      expect(releases.last['activeArtifacts'], hasLength(2));
    });

    test('is empty for a track without releases', () async {
      final response = await get('$_api/tracks/beta/releases');

      expect(json(response)['releases'], isEmpty);
    });
  });

  group('misbehaving', () {
    test('failNext fails the next matching request once', () async {
      server.failNext(
        503,
        message: 'Backend Error',
        pathContains: '/edits',
        method: 'POST',
      );

      final first = await post('$_api/edits');
      final second = await post('$_api/edits');

      expect(first.statusCode, 503);
      expect(error(first)['message'], 'Backend Error');
      expect(error(first)['status'], 'UNAVAILABLE');
      expect(second.statusCode, 200);
    });

    test('failNext keeps its reason and skips other methods', () async {
      server.failNext(409, reason: 'conflict', method: 'DELETE');

      expect((await post('$_api/edits')).statusCode, 200);
      final id = await insertEdit();
      final response = await post('$_api/edits/$id', method: 'DELETE');

      expect(response.statusCode, 409);
      expect(error(response)['status'], 'ABORTED');
      expect(
        ((error(response)['errors'] as List).single as Map)['reason'],
        'conflict',
      );
    });

    test('failNext knows the status names', () async {
      for (final (status, name) in [
        (400, 'INVALID_ARGUMENT'),
        (401, 'UNAUTHENTICATED'),
        (403, 'PERMISSION_DENIED'),
        (404, 'NOT_FOUND'),
        (500, 'INTERNAL'),
      ]) {
        server.failNext(status);
        expect(error(await post('$_api/edits'))['status'], name);
      }
    });

    test('rateLimitNext answers 429 with Retry-After', () async {
      server.rateLimitNext(2, retryAfterSeconds: 7);

      final first = await post('$_api/edits');
      final second = await post('$_api/edits');
      final third = await post('$_api/edits');

      expect(first.statusCode, 429);
      expect(first.headers['retry-after'], '7');
      expect(error(first)['status'], 'RESOURCE_EXHAUSTED');
      expect(second.statusCode, 429);
      expect(third.statusCode, 200);
    });

    test('rateLimitNext without Retry-After sends none', () async {
      server.rateLimitNext(1);

      final response = await post('$_api/edits');

      expect(response.statusCode, 429);
      expect(response.headers.containsKey('retry-after'), isFalse);
    });
  });

  test('records every request with its token check', () async {
    await post('$_api/edits');
    await post('$_api/edits', bearer: 'nope');

    final api = server.requests.where((r) => r.uri.path != '/token');
    expect(api.map((r) => '$r'), ['POST $_api/edits', 'POST $_api/edits']);
    expect(api.map((r) => r.tokenProblem), [isNull, isNotNull]);
  });

  test('a bundle is made from its version code', () {
    expect(utf8.decode(fakeAab(7, padding: 3)), 'fake-aab versionCode=7\nxxx');
  });
}
