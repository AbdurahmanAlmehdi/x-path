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

  group('build uploads', () {
    late FakeAscApp app;
    final ipa = utf8.encode('twelve bytes');
    // MD5 of "twelve bytes".
    const md5 = 'c91fa94e14cf2fa5474beceff788c0dc';

    setUp(() {
      app = server.addApp('ly.example.app');
      server.uploadPartSize = 5;
    });

    Map<String, Object?> link(String type, String id) => {
      'data': {'type': type, 'id': id},
    };

    Future<http.Response> createUpload({String buildNumber = '42'}) => call(
      'POST',
      '/v1/buildUploads',
      body: {
        'data': {
          'type': 'buildUploads',
          'attributes': {
            'cfBundleShortVersionString': '1.0.0',
            'cfBundleVersion': buildNumber,
            'platform': 'IOS',
          },
          'relationships': {'app': link('apps', app.id)},
        },
      },
    );

    Future<http.Response> createFile(String uploadId) => call(
      'POST',
      '/v1/buildUploadFiles',
      body: {
        'data': {
          'type': 'buildUploadFiles',
          'attributes': {
            'assetType': 'ASSET',
            'fileName': 'app.ipa',
            'fileSize': ipa.length,
            'uti': 'com.apple.ipa',
          },
          'relationships': {'buildUpload': link('buildUploads', uploadId)},
        },
      },
    );

    Future<http.Response> put(Uri url, List<int> bytes) async {
      final request = http.Request('PUT', url)
        ..headers['Content-Type'] = 'application/octet-stream'
        ..bodyBytes = bytes;
      return await http.Response.fromStream(await client.send(request));
    }

    Future<http.Response> commit(String fileId, {String hash = md5}) => call(
      'PATCH',
      '/v1/buildUploadFiles/$fileId',
      body: {
        'data': {
          'type': 'buildUploadFiles',
          'id': fileId,
          'attributes': {
            'uploaded': true,
            'sourceFileChecksums': {
              'file': {'hash': hash, 'algorithm': 'MD5'},
            },
          },
        },
      },
    );

    Map<String, dynamic> attributes(http.Response response) =>
        (json(response)['data'] as Map<String, dynamic>)['attributes']
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> state(String uploadId) async =>
        attributes(await call('GET', '/v1/buildUploads/$uploadId'))['state']
            as Map<String, dynamic>;

    /// Creates an upload, sends its parts and marks it uploaded.
    Future<String> send() async {
      final upload =
          (json(await createUpload())['data'] as Map)['id'] as String;
      final file = await createFile(upload);
      for (final operation
          in attributes(file)['uploadOperations'] as List<dynamic>) {
        final part = operation as Map<String, dynamic>;
        final offset = part['offset'] as int;
        await put(
          Uri.parse(part['url'] as String),
          ipa.sublist(offset, offset + (part['length'] as int)),
        );
      }
      await commit((json(file)['data'] as Map)['id'] as String);
      return upload;
    }

    test('go from parts to a build', () async {
      final created = await createUpload();
      expect(created.statusCode, 201);
      final upload = (json(created)['data'] as Map)['id'] as String;
      expect((await state(upload))['state'], 'AWAITING_UPLOAD');

      final file = await createFile(upload);
      expect(file.statusCode, 201);
      final operations = [
        for (final operation
            in attributes(file)['uploadOperations'] as List<dynamic>)
          operation as Map<String, dynamic>,
      ];
      expect(operations.map((o) => (o['offset'], o['length'])), [
        (0, 5),
        (5, 5),
        (10, 2),
      ]);
      expect(operations.first['requestHeaders'], [
        {'name': 'Content-Type', 'value': 'application/octet-stream'},
      ]);
      for (final operation in operations) {
        final offset = operation['offset'] as int;
        final response = await put(
          Uri.parse(operation['url'] as String),
          ipa.sublist(offset, offset + (operation['length'] as int)),
        );
        expect(response.statusCode, 200);
      }
      final fileId = (json(file)['data'] as Map)['id'] as String;
      final committed = await commit(fileId);
      expect(committed.statusCode, 200);
      expect(attributes(committed)['assetDeliveryState'], {
        'state': 'COMPLETE',
      });

      expect((await state(upload))['state'], 'PROCESSING');
      final done = await call('GET', '/v1/buildUploads/$upload');
      expect(attributes(done)['state'], {
        'state': 'COMPLETE',
        'errors': <Object?>[],
        'warnings': <Object?>[],
        'infos': <Object?>[],
      });
      final build = server.builds.single;
      expect(((json(done)['data'] as Map)['relationships'] as Map)['build'], {
        'data': {'type': 'builds', 'id': build.id},
      });
      expect(build.buildNumber, '42');
      expect(build.shortVersion, '1.0.0');
      expect(build.processingState, 'PROCESSING');
      expect(server.uploadFiles[fileId]!.bytes, ipa);
      expect(
        server.requests
            .where((r) => r.uri.path.startsWith('/upload/'))
            .map((r) => r.authorization)
            .toSet(),
        {null},
      );
    });

    test('end the way the outcomes say', () async {
      server.uploadOutcomes.addAll(const [
        FakeAscUploadOutcome.rejected([FakeAscIssue('90189', 'Used.')]),
        FakeAscUploadOutcome.stalled(),
        FakeAscUploadOutcome.complete(warnings: [FakeAscIssue('1', 'Hm.')]),
      ]);

      final rejected = await send();
      final stalled = await send();
      final warned = await send();
      for (final upload in [rejected, stalled, warned]) {
        await state(upload);
      }

      expect(await state(rejected), {
        'state': 'FAILED',
        'errors': [
          {'code': '90189', 'description': 'Used.'},
        ],
        'warnings': <Object?>[],
        'infos': <Object?>[],
      });
      expect((await state(stalled))['state'], 'PROCESSING');
      expect((await state(warned))['warnings'], [
        {'code': '1', 'description': 'Hm.'},
      ]);
      expect(server.builds, hasLength(1));
    });

    test('refuse a build number App Store Connect has', () async {
      server.addBuild(app.id, buildNumber: '42', version: '1.0.0');

      final response = await createUpload();

      expect(response.statusCode, 409);
      expect(
        (json(response)['errors'] as List<dynamic>).single,
        containsPair('code', 'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE'),
      );
    });

    Future<String> uploadId() async =>
        (json(await createUpload())['data'] as Map)['id'] as String;

    /// A file of a new upload, with its operations.
    Future<(String, List<Map<String, dynamic>>)> newFile() async {
      final file = await createFile(await uploadId());
      return (
        (json(file)['data'] as Map)['id'] as String,
        [
          for (final operation
              in attributes(file)['uploadOperations'] as List<dynamic>)
            operation as Map<String, dynamic>,
        ],
      );
    }

    Future<void> sendAll(List<Map<String, dynamic>> operations) async {
      for (final operation in operations) {
        final offset = operation['offset'] as int;
        await put(
          Uri.parse(operation['url'] as String),
          ipa.sublist(offset, offset + (operation['length'] as int)),
        );
      }
    }

    test('refuse an upload without its version', () async {
      final response = await call(
        'POST',
        '/v1/buildUploads',
        body: {
          'data': {
            'type': 'buildUploads',
            'relationships': {'app': link('apps', app.id)},
          },
        },
      );

      expect(response.statusCode, 409);
    });

    test('refuse a file that is not an IPA', () async {
      final response = await call(
        'POST',
        '/v1/buildUploadFiles',
        body: {
          'data': {
            'type': 'buildUploadFiles',
            'attributes': {'fileName': 'app.ipa', 'fileSize': 12},
            'relationships': {
              'buildUpload': link('buildUploads', await uploadId()),
            },
          },
        },
      );

      expect(response.statusCode, 409);
    });

    test('refuse a second file of an upload', () async {
      final upload = await uploadId();
      await createFile(upload);

      expect((await createFile(upload)).statusCode, 409);
    });

    test('refuse a part of the wrong size', () async {
      final (_, operations) = await newFile();

      final response = await put(
        Uri.parse(operations.first['url'] as String),
        ipa,
      );

      expect(response.statusCode, 400);
    });

    test('refuse to mark a file uploaded before every part is in', () async {
      final (file, _) = await newFile();

      expect((await commit(file)).statusCode, 409);
    });

    test('refuse a wrong checksum, or none', () async {
      final (file, operations) = await newFile();
      await sendAll(operations);
      final none = await call(
        'PATCH',
        '/v1/buildUploadFiles/$file',
        body: {
          'data': {
            'type': 'buildUploadFiles',
            'id': file,
            'attributes': {'uploaded': true},
          },
        },
      );

      expect((await commit(file, hash: '0' * 32)).statusCode, 409);
      expect(none.statusCode, 409);
      expect((await commit(file)).statusCode, 200);
    });

    test('record the media type of each part', () async {
      final (_, operations) = await newFile();
      await sendAll(operations);

      expect(
        server.requests
            .where((request) => request.uri.path.startsWith('/upload/'))
            .map((request) => request.contentType),
        everyElement('application/octet-stream'),
      );
    });

    test('answer 404 for what does not exist', () async {
      final upload =
          (json(await createUpload())['data'] as Map)['id'] as String;
      final file =
          (json(await createFile(upload))['data'] as Map)['id'] as String;

      expect((await call('GET', '/v1/buildUploads/nope')).statusCode, 404);
      expect((await createFile('nope')).statusCode, 404);
      expect((await commit('nope')).statusCode, 404);
      for (final path in [
        '/upload/nope/0',
        '/upload/$file/9',
        '/upload/$file/-1',
        '/upload/$file/x',
        '/upload/$file',
      ]) {
        expect(
          (await put(server.baseUrl.replace(path: path), [1])).statusCode,
          404,
          reason: path,
        );
      }
      final get = await http.Response.fromStream(
        await client.send(
          http.Request('GET', server.baseUrl.replace(path: '/upload/$file/0')),
        ),
      );
      expect(get.statusCode, 404);
    });

    test('a file of no bytes is sent in one empty part', () {
      final file = FakeAscUploadFile(
        id: 'f',
        uploadId: 'u',
        fileName: 'empty.ipa',
        fileSize: 0,
        partSize: 5,
      );

      expect(file.partCount, 1);
      expect(file.bytes, isNull);
      file.parts[0] = const [];
      expect(file.bytes, isEmpty);
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

  group('profiles', () {
    Map<String, Object?> profile({
      String name = 'XPath app',
      String bundleId = 'bundle-1',
      String certificate = 'cert-1',
    }) => {
      'data': {
        'type': 'profiles',
        'attributes': {'name': name, 'profileType': 'IOS_APP_STORE'},
        'relationships': {
          'bundleId': {
            'data': {'type': 'bundleIds', 'id': bundleId},
          },
          'certificates': {
            'data': [
              {'type': 'certificates', 'id': certificate},
            ],
          },
        },
      },
    };

    setUp(() {
      server
        ..certificates['cert-1'] = FakeAscCertificate(
          id: 'cert-1',
          serialNumber: '0A',
          certificateType: 'DISTRIBUTION',
          content: [1],
        )
        ..bundleIds['ly.app'] = 'bundle-1';
    });

    test('are created for a bundle id and certificate, and listed', () async {
      final created = await call('POST', '/v1/profiles', body: profile());

      expect(created.statusCode, 201);
      expect(
        ids(
          await call(
            'GET',
            '/v1/profiles',
            query: {'filter[name]': 'XPath app'},
          ),
        ),
        [server.profiles.keys.single],
      );
      expect(ids(await call('GET', '/v1/certificates')), ['cert-1']);
      expect(
        ids(
          await call(
            'GET',
            '/v1/bundleIds',
            query: {'filter[identifier]': 'ly'},
          ),
        ),
        ['bundle-1'],
      );
    });

    test('certificates are created from a PEM request', () async {
      Map<String, Object?> certificate(String csr) => {
        'data': {
          'type': 'certificates',
          'attributes': {'certificateType': 'DISTRIBUTION', 'csrContent': csr},
        },
      };

      final created = await call(
        'POST',
        '/v1/certificates',
        body: certificate('-----BEGIN CERTIFICATE REQUEST-----\nx'),
      );
      final refused = await call(
        'POST',
        '/v1/certificates',
        body: certificate('x'),
      );

      expect(created.statusCode, 201);
      expect(
        ((json(created)['data'] as Map)['attributes'] as Map)['serialNumber'],
        fakeDistributionSerial,
      );
      expect(refused.statusCode, 409);
    });

    test('refuse what does not exist or is not complete', () async {
      for (final (body, status) in [
        (
          {
            'data': {'type': 'profiles'},
          },
          409,
        ),
        (profile(bundleId: 'nope'), 404),
        (profile(certificate: 'nope'), 404),
      ]) {
        expect(
          (await call('POST', '/v1/profiles', body: body)).statusCode,
          status,
          reason: '$body',
        );
      }
      expect(server.profiles, isEmpty);
    });
  });
}
