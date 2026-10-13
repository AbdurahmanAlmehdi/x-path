import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

import 'helpers/mint.dart';

void main() {
  late FakeAscServer server;
  late http.Client client;

  setUp(() async {
    server = await FakeAscServer.start(now: () => testNow);
    client = http.Client();
    addTearDown(() async {
      client.close();
      await server.close();
    });
  });

  Future<http.Response> call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? token,
    bool anonymous = false,
  }) async {
    final request = http.Request(
      method,
      server.baseUrl.replace(path: path, queryParameters: query),
    );
    if (!anonymous) {
      request.headers['Authorization'] = 'Bearer ${token ?? mint()}';
    }
    if (body != null) request.body = jsonEncode(body);
    return await http.Response.fromStream(await client.send(request));
  }

  Map<String, dynamic> json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  List<String> ids(http.Response response) => [
    for (final item in json(response)['data'] as List<dynamic>)
      (item as Map<String, dynamic>)['id'] as String,
  ];

  group('the token', () {
    test('is checked and the reason is in the error', () async {
      final response = await call('GET', '/v1/apps', token: mint(tamper: true));

      expect(response.statusCode, 401);
      final error =
          (json(response)['errors'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(error['code'], 'NOT_AUTHORIZED');
      expect(error['detail'], 'The signature does not match the key.');
      expect(server.requests.single.tokenProblem, isNotNull);
    });

    test('is required', () async {
      final response = await call('GET', '/v1/apps', anonymous: true);

      expect(response.statusCode, 401);
    });
  });

  group('apps', () {
    test('are found by bundle id', () async {
      final app = server.addApp('ly.example.app', name: 'Example');
      server.addApp('ly.example.other');

      final response = await call(
        'GET',
        '/v1/apps',
        query: {'filter[bundleId]': 'ly.example.app'},
      );

      expect(ids(response), [app.id]);
      final data =
          (json(response)['data'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(data['attributes'], {
        'name': 'Example',
        'bundleId': 'ly.example.app',
      });
    });

    test('are all listed without a filter', () async {
      server
        ..addApp('a')
        ..addApp('b');

      expect(ids(await call('GET', '/v1/apps')), hasLength(2));
    });
  });

  group('builds', () {
    test('are filtered and listed newest first with their train', () async {
      final app = server.addApp('ly.example.app');
      final other = server.addApp('ly.example.other');
      final first = server.addBuild(
        app.id,
        buildNumber: '44',
        version: '1.2.3',
        processingState: 'PROCESSING',
      );
      final second = server.addBuild(
        app.id,
        buildNumber: '45',
        version: '1.2.3',
      );
      server
        ..addBuild(app.id, buildNumber: '45', version: '1.2.4')
        ..addBuild(other.id, buildNumber: '45', version: '1.2.3');

      final all = await call(
        'GET',
        '/v1/builds',
        query: {'filter[app]': app.id, 'include': 'preReleaseVersion'},
      );
      final one = await call(
        'GET',
        '/v1/builds',
        query: {
          'filter[app]': app.id,
          'filter[version]': '45',
          'filter[preReleaseVersion.version]': '1.2.3',
          'filter[processingState]': 'VALID',
        },
      );

      expect(ids(all), hasLength(3));
      expect(ids(all).last, first.id);
      expect(ids(one), [second.id]);
      final included = json(all)['included'] as List<dynamic>;
      expect([
        for (final train in included)
          ((train as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>)['version'],
      ], unorderedEquals(['1.2.3', '1.2.4']));
      expect(json(one).containsKey('included'), isFalse);
    });

    test('are paged with links.next', () async {
      final app = server.addApp('ly.example.app');
      for (var i = 1; i <= 5; i++) {
        server.addBuild(app.id, buildNumber: '$i', version: '1.0.0');
      }

      final firstPage = await call(
        'GET',
        '/v1/builds',
        query: {'filter[app]': app.id, 'limit': '2'},
      );
      final next = Uri.parse(
        (json(firstPage)['links'] as Map<String, dynamic>)['next'] as String,
      );
      final secondPage = await call(
        'GET',
        next.path,
        query: next.queryParameters,
      );
      final last = await call(
        'GET',
        '/v1/builds',
        query: {'filter[app]': app.id, 'limit': '2', 'cursor': '4'},
      );

      expect(ids(firstPage), hasLength(2));
      expect(ids(secondPage), hasLength(2));
      expect(ids(last), hasLength(1));
      expect(
        (json(last)['links'] as Map<String, dynamic>).containsKey('next'),
        isFalse,
      );
    });
  });

  group('App Store versions', () {
    test('carry appVersionState and a deprecated appStoreState', () async {
      final app = server.addApp('ly.example.app');
      server
        ..addVersion(
          app.id,
          '1.2.2',
          appVersionState: 'READY_FOR_DISTRIBUTION',
          createdDate: DateTime.utc(2026, 8),
        )
        ..addVersion(
          app.id,
          '1.2.3',
          appVersionState: 'PENDING_DEVELOPER_RELEASE',
          createdDate: DateTime.utc(2026, 9),
        )
        ..addVersion(app.id, '1.0.0', platform: 'MAC_OS');

      final response = await call(
        'GET',
        '/v1/apps/${app.id}/appStoreVersions',
        query: {'filter[platform]': 'IOS'},
      );

      final data = (json(response)['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        [for (final v in data) (v['attributes'] as Map)['versionString']],
        ['1.2.3', '1.2.2'],
      );
      final attributes = data.first['attributes'] as Map<String, dynamic>;
      expect(attributes['appVersionState'], 'PENDING_DEVELOPER_RELEASE');
      expect(attributes['appStoreState'], 'LEGACY_PENDING_DEVELOPER_RELEASE');
    });

    test('are not listed for an unknown app', () async {
      final response = await call('GET', '/v1/apps/404/appStoreVersions');

      expect(response.statusCode, 404);
    });

    test('are all listed without a platform filter', () async {
      final app = server.addApp('ly.example.app');
      server
        ..addVersion(app.id, '1.0.0')
        ..addVersion(app.id, '1.1.0', platform: 'MAC_OS');

      final response = await call('GET', '/v1/apps/${app.id}/appStoreVersions');

      expect(ids(response), hasLength(2));
    });
  });

  group('review submissions', () {
    late FakeAscApp app;
    late FakeAscVersion version;

    setUp(() {
      app = server.addApp('ly.example.app');
      version = server.addVersion(app.id, '1.2.3');
    });

    Future<http.Response> create() => call(
      'POST',
      '/v1/reviewSubmissions',
      body: {
        'data': {
          'type': 'reviewSubmissions',
          'attributes': {'platform': 'IOS'},
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': app.id},
            },
          },
        },
      },
    );

    Future<http.Response> addItem(String submissionId, String versionId) =>
        call(
          'POST',
          '/v1/reviewSubmissionItems',
          body: {
            'data': {
              'type': 'reviewSubmissionItems',
              'relationships': {
                'reviewSubmission': {
                  'data': {'type': 'reviewSubmissions', 'id': submissionId},
                },
                'appStoreVersion': {
                  'data': {'type': 'appStoreVersions', 'id': versionId},
                },
              },
            },
          },
        );

    Future<http.Response> submit(String id) => call(
      'PATCH',
      '/v1/reviewSubmissions/$id',
      body: {
        'data': {
          'type': 'reviewSubmissions',
          'id': id,
          'attributes': {'submitted': true},
        },
      },
    );

    test('are created, filled, submitted and read', () async {
      final created = await create();
      final id =
          (json(created)['data'] as Map<String, dynamic>)['id'] as String;

      expect(created.statusCode, 201);
      expect(server.submissions[id]!.state, 'READY_FOR_REVIEW');
      expect((await addItem(id, version.id)).statusCode, 201);

      final submitted = await submit(id);

      expect(submitted.statusCode, 200);
      final read = await call('GET', '/v1/reviewSubmissions/$id');
      final attributes =
          (json(read)['data'] as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>;
      expect(attributes['state'], 'WAITING_FOR_REVIEW');
      expect(attributes['submittedDate'], testNow.toIso8601String());
      expect(version.appVersionState, 'WAITING_FOR_REVIEW');
      expect(ids(await call('GET', '/v1/apps/${app.id}/reviewSubmissions')), [
        id,
      ]);
    });

    test('cannot be submitted empty', () async {
      final id =
          (json(await create())['data'] as Map<String, dynamic>)['id']
              as String;

      final response = await submit(id);

      expect(response.statusCode, 409);
      expect(server.submissions[id]!.state, 'READY_FOR_REVIEW');
    });

    test('are updated without being submitted', () async {
      final id =
          (json(await create())['data'] as Map<String, dynamic>)['id']
              as String;

      final response = await call(
        'PATCH',
        '/v1/reviewSubmissions/$id',
        body: {
          'data': {'type': 'reviewSubmissions', 'id': id},
        },
      );

      expect(response.statusCode, 200);
      expect(server.submissions[id]!.state, 'READY_FOR_REVIEW');
    });

    test('refuse what does not exist or is not complete', () async {
      final id =
          (json(await create())['data'] as Map<String, dynamic>)['id']
              as String;

      expect((await call('GET', '/v1/reviewSubmissions/nope')).statusCode, 404);
      expect((await addItem(id, 'nope')).statusCode, 404);
      expect((await addItem('nope', version.id)).statusCode, 404);
      expect(
        (await call(
          'POST',
          '/v1/reviewSubmissions',
          body: {'x': 1},
        )).statusCode,
        400,
      );
      expect(
        (await call(
          'POST',
          '/v1/reviewSubmissions',
          body: {
            'data': {'type': 'reviewSubmissions'},
          },
        )).statusCode,
        409,
      );
      expect(
        (await call('GET', '/v1/apps/nope/reviewSubmissions')).statusCode,
        404,
      );
    });

    test('are created with the default platform', () async {
      final response = await call(
        'POST',
        '/v1/reviewSubmissions',
        body: {
          'data': {
            'type': 'reviewSubmissions',
            'relationships': {
              'app': {
                'data': {'type': 'apps', 'id': app.id},
              },
            },
          },
        },
      );

      expect(response.statusCode, 201);
      expect(server.submissions.values.single.platform, 'IOS');
    });
  });

  group('phased releases', () {
    late FakeAscVersion version;

    setUp(() {
      final app = server.addApp('ly.example.app');
      version = server.addVersion(app.id, '1.2.3');
    });

    test('are read and updated', () async {
      final release = server.addPhasedRelease(
        version.id,
        state: 'ACTIVE',
        currentDayNumber: 3,
      );

      final read = await call(
        'GET',
        '/v1/appStoreVersions/${version.id}/appStoreVersionPhasedRelease',
      );
      final paused = await call(
        'PATCH',
        '/v1/appStoreVersionPhasedReleases/${release.id}',
        body: {
          'data': {
            'type': 'appStoreVersionPhasedReleases',
            'id': release.id,
            'attributes': {'phasedReleaseState': 'PAUSED'},
          },
        },
      );

      final attributes =
          (json(read)['data'] as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>;
      expect(attributes['phasedReleaseState'], 'ACTIVE');
      expect(attributes['currentDayNumber'], 3);
      expect(paused.statusCode, 200);
      expect(release.state, 'PAUSED');
    });

    test('are 404 when the version has none or does not exist', () async {
      expect(
        (await call(
          'GET',
          '/v1/appStoreVersions/${version.id}/appStoreVersionPhasedRelease',
        )).statusCode,
        404,
      );
      expect(
        (await call(
          'GET',
          '/v1/appStoreVersions/nope/appStoreVersionPhasedRelease',
        )).statusCode,
        404,
      );
    });

    test('refuse an unknown release or state', () async {
      final release = server.addPhasedRelease(version.id);
      Future<http.Response> patch(String id, Object? state) => call(
        'PATCH',
        '/v1/appStoreVersionPhasedReleases/$id',
        body: {
          'data': {
            'attributes': {'phasedReleaseState': state},
          },
        },
      );

      expect((await patch('nope', 'ACTIVE')).statusCode, 404);
      expect((await patch(release.id, 'SIDEWAYS')).statusCode, 422);
      expect(release.state, 'INACTIVE');
    });
  });

  group('misbehaviour', () {
    test('answers 429 with Retry-After for the requests asked for', () async {
      server.rateLimitNext(2, retryAfterSeconds: 7);

      final first = await call('GET', '/v1/apps');
      final second = await call('GET', '/v1/apps');
      final third = await call('GET', '/v1/apps');

      expect(first.statusCode, 429);
      expect(first.headers['retry-after'], '7');
      expect(second.statusCode, 429);
      expect(third.statusCode, 200);
    });

    test('answers 429 without Retry-After', () async {
      server.rateLimitNext(1);

      final response = await call('GET', '/v1/apps');

      expect(response.statusCode, 429);
      expect(response.headers.containsKey('retry-after'), isFalse);
    });

    test('fails the next request under a path with the error given', () async {
      server.failNext(
        503,
        code: 'SERVICE_UNAVAILABLE',
        title: 'Down',
        detail: 'Try later.',
        pathPrefix: '/v1/builds',
      );

      final other = await call('GET', '/v1/apps');
      final failed = await call('GET', '/v1/builds');
      final again = await call('GET', '/v1/builds');

      expect(other.statusCode, 200);
      expect(failed.statusCode, 503);
      expect(
        (json(failed)['errors'] as List<dynamic>).single,
        containsPair('detail', 'Try later.'),
      );
      expect(again.statusCode, 200);
    });

    test('reports the quota left in X-Rate-Limit', () async {
      final first = await call('GET', '/v1/apps');
      final second = await call('GET', '/v1/apps');

      expect(
        first.headers['x-rate-limit'],
        'user-hour-lim:3500;user-hour-rem:3499;',
      );
      expect(
        second.headers['x-rate-limit'],
        'user-hour-lim:3500;user-hour-rem:3498;',
      );
    });

    test('answers 404 for a path it does not serve', () async {
      expect((await call('GET', '/v2/apps')).statusCode, 404);
      expect((await call('GET', '/v1/nothing')).statusCode, 404);
      expect((await call('GET', '/')).statusCode, 404);
    });
  });

  group('the iTunes lookup', () {
    test('needs no token and answers per storefront', () async {
      server.addItunes('ly.example.app', version: '1.2.2', trackId: '555');

      final us = await call(
        'GET',
        '/lookup',
        query: {'bundleId': 'ly.example.app', 'country': 'us'},
        anonymous: true,
      );
      final sa = await call(
        'GET',
        '/lookup',
        query: {'bundleId': 'ly.example.app', 'country': 'sa'},
        anonymous: true,
      );

      expect(json(us)['resultCount'], 1);
      final result =
          (json(us)['results'] as List<dynamic>).single as Map<String, dynamic>;
      expect(result['version'], '1.2.2');
      expect(result['trackId'], 555);
      expect(json(sa), {'resultCount': 0, 'results': <Object?>[]});
    });
  });
}
