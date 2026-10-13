import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

import 'helpers/mint.dart';

const _appId = '1:684690133351:android:b434734f585770367c1fc2';
const _app = 'projects/684690133351/apps/$_appId';

void main() {
  late FakeFirebaseServer server;
  late http.Client client;
  late String token;

  Future<String> issue({
    String privateKeyPem = fakePlayPrivateKeyPem,
    Map<String, Object?> claims = const {},
  }) async {
    final response = await client.post(
      server.tokenUri,
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': mint(
          server.tokenUri,
          claims: claims,
          privateKeyPem: privateKeyPem,
        ),
      },
    );
    return response.statusCode == 200
        ? (jsonDecode(response.body) as Map<String, dynamic>)['access_token']
              as String
        : response.body;
  }

  Future<http.Response> call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    Map<String, String> headers = const {},
    String? bearer,
  }) async {
    final request = http.Request(method, server.baseUrl.resolve(path))
      ..headers['Authorization'] = 'Bearer ${bearer ?? token}'
      ..headers.addAll(headers);
    if (json != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(json);
    }
    if (bytes != null) request.bodyBytes = bytes;
    return await http.Response.fromStream(await client.send(request));
  }

  Map<String, dynamic> body(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  /// The value at [path] of nested maps and lists.
  Object? at(Object? json, List<Object> path) {
    var value = json;
    for (final key in path) {
      value = key is int ? (value! as List)[key] : (value! as Map)[key];
    }
    return value;
  }

  Future<http.Response> upload(
    List<int> bytes, {
    Map<String, String>? headers,
  }) => call(
    'POST',
    '/upload/v1/$_app/releases:upload',
    bytes: bytes,
    headers:
        headers ??
        {'X-Goog-Upload-Protocol': 'raw', 'X-Goog-Upload-File-Name': 'app.apk'},
  );

  List<int> apk(String name, int code, {int padding = 0}) =>
      fakeBinary('apk', versionName: name, versionCode: code, padding: padding);

  setUp(() async {
    server = await FakeFirebaseServer.start()
      ..addApp('684690133351', _appId, groups: {'qa'});
    client = http.Client();
    token = await issue();
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  group('the token endpoint', () {
    test('issues a token for a valid assertion', () {
      expect(token, startsWith('ya29.fake-'));
      expect(server.tokensIssued, 1);
    });

    test('refuses the Play scope, an unknown key and another grant', () async {
      expect(
        await issue(claims: {'scope': fakePlayScope}),
        contains('The scope must be'),
      );
      expect(
        await issue(privateKeyPem: fakePlayOtherPrivateKeyPem),
        contains('Invalid JWT Signature'),
      );
      final other = await client.post(
        server.tokenUri,
        body: {'grant_type': 'password'},
      );
      expect(other.statusCode, 400);
      expect(at(body(other), ['error']), 'unsupported_grant_type');
    });

    test('makes a key file that points at it', () {
      final json = jsonDecode(server.serviceAccountJson()) as Map;

      expect(json['token_uri'], '${server.tokenUri}');
      expect(json['client_email'], fakePlayClientEmail);
    });
  });

  group('access', () {
    test('refuses a missing, unknown or revoked token', () async {
      expect(
        (await call('GET', '/v1/$_app/releases', bearer: 'nope')).statusCode,
        401,
      );

      server.revokeTokens();
      final revoked = await call('GET', '/v1/$_app/releases');
      expect(revoked.statusCode, 401);
      expect(at(body(revoked), ['error', 'status']), 'UNAUTHENTICATED');
    });

    test('refuses an expired token', () async {
      final now = DateTime.utc(2026, 10, 13, 12);
      var clock = now;
      final short = await FakeFirebaseServer.start(
        now: () => clock,
        tokenLifetime: const Duration(minutes: 5),
      );
      addTearDown(short.close);
      short.addApp('1', '1:1:android:a');
      final response = await client.post(
        short.tokenUri,
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': mint(
            short.tokenUri,
            claims: {
              'iat': now.millisecondsSinceEpoch ~/ 1000,
              'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
            },
          ),
        },
      );
      final expiring =
          (jsonDecode(response.body) as Map)['access_token'] as String;
      clock = now.add(const Duration(minutes: 6));

      final result = await client.get(
        short.baseUrl.resolve('/v1/projects/1/apps/1:1:android:a/releases'),
        headers: {'Authorization': 'Bearer $expiring'},
      );

      expect(result.statusCode, 401);
      expect(result.body, contains('has expired'));
    });

    test(
      'answers 404 for an unknown app and 403 for an account not allowed',
      () async {
        expect(
          (await call(
            'GET',
            '/v1/projects/684690133351/apps/1:1:android:zz/releases',
          )).statusCode,
          404,
        );
        expect(
          (await call(
            'GET',
            '/v1/projects/999/apps/$_appId/releases',
          )).statusCode,
          404,
        );
        server.apps[_appId]!.allowedAccounts = {'someone@else'};

        final denied = await call('GET', '/v1/$_app/releases');

        expect(denied.statusCode, 403);
        expect(at(body(denied), ['error', 'status']), 'PERMISSION_DENIED');
      },
    );

    test('answers 404 for a method it does not have', () async {
      expect((await call('GET', '/v1/nope')).statusCode, 404);
      expect((await call('DELETE', '/v1/$_app/releases')).statusCode, 404);
    });

    test('fails a request on demand, or throttles', () async {
      server.failNext(503, message: 'Backend error', pathContains: 'releases');

      final failed = await call('GET', '/v1/$_app/releases');
      expect(failed.statusCode, 503);
      expect(at(body(failed), ['error', 'message']), 'Backend error');
      expect((await call('GET', '/v1/$_app/releases')).statusCode, 200);

      server
        ..failNext(400, method: 'PATCH')
        ..failNext(409)
        ..failNext(418)
        ..failNext(404);
      expect((await call('GET', '/v1/$_app/releases')).statusCode, 409);
      expect((await call('GET', '/v1/$_app/releases')).statusCode, 418);
      expect((await call('GET', '/v1/$_app/releases')).statusCode, 404);

      server.rateLimitNext(1, retryAfterSeconds: 7);
      final limited = await call('GET', '/v1/$_app/releases');
      expect(limited.statusCode, 429);
      expect(limited.headers['retry-after'], '7');
      server.rateLimitNext(1);
      expect(
        (await call('GET', '/v1/$_app/releases')).headers['retry-after'],
        isNull,
      );
    });

    test('records every request', () async {
      await call('GET', '/v1/$_app/releases');

      final request = server.requests.last;
      expect(request.method, 'GET');
      expect(request.uri.path, '/v1/$_app/releases');
      expect(request.tokenProblem, isNull);
      expect(request.headers['authorization'], 'Bearer $token');
    });
  });

  group('upload', () {
    test(
      'makes a release and an operation that is done after the polls',
      () async {
        final response = await upload(apk('1.2.3', 45));

        expect(response.statusCode, 200);
        final operation = body(response);
        expect(operation['done'], isNull);
        final name = operation['name'] as String;
        expect(name, startsWith('$_app/releases/-/operations/'));

        final poll = await call('GET', '/v1/$name');
        expect(at(body(poll), ['done']), isTrue);
        final result = at(body(poll), ['response'])! as Map<String, dynamic>;
        expect(result['result'], 'RELEASE_CREATED');
        final release = result['release'] as Map<String, dynamic>;
        expect(release['displayVersion'], '1.2.3');
        expect(release['buildVersion'], '45');
        expect(release['binaryType'], 'APK');
        expect(release['name'], startsWith('$_app/releases/'));
      },
    );

    test('lets the test choose how long the operation takes', () async {
      server.pollsBeforeDone = 0;

      expect(at(body(await upload(apk('1.2.3', 45))), ['done']), isTrue);

      server.pollsBeforeDone = 2;
      final name =
          at(body(await upload(apk('1.2.3', 46))), ['name'])! as String;
      expect(at(body(await call('GET', '/v1/$name')), ['done']), isNull);
      expect(at(body(await call('GET', '/v1/$name')), ['done']), isTrue);
    });

    test(
      'finds the release of the same version: unmodified or updated',
      () async {
        server.pollsBeforeDone = 0;
        await upload(apk('1.2.3', 45));

        final same = await upload(apk('1.2.3', 45));
        final changed = await upload(apk('1.2.3', 45, padding: 10));

        expect(at(body(same), ['response', 'result']), 'RELEASE_UNMODIFIED');
        expect(at(body(changed), ['response', 'result']), 'RELEASE_UPDATED');
        expect(server.apps[_appId]!.releases, hasLength(1));
      },
    );

    test('takes an AAB and an IPA', () async {
      server.pollsBeforeDone = 0;
      final aab = await upload(
        fakeBinary('aab', versionName: '1.0.0', versionCode: 1),
      );
      final ipa = await upload(
        fakeBinary('ipa', versionName: '1.0.0', versionCode: 2),
      );

      expect(at(body(aab), ['response', 'release', 'binaryType']), 'AAB');
      expect(at(body(ipa), ['response', 'release', 'binaryType']), 'IPA');
    });

    test(
      'refuses the wrong protocol, a missing file name and a bad binary',
      () async {
        for (final response in [
          await upload(
            apk('1.0.0', 1),
            headers: {'X-Goog-Upload-File-Name': 'a.apk'},
          ),
          await upload(
            apk('1.0.0', 1),
            headers: {'X-Goog-Upload-Protocol': 'raw'},
          ),
          await upload(utf8.encode('not a binary')),
        ]) {
          expect(response.statusCode, 400);
          expect(at(body(response), ['error', 'status']), 'INVALID_ARGUMENT');
        }
      },
    );

    test('does not take an upload to another path', () async {
      final response = await call(
        'POST',
        '/v1/$_app/releases:upload',
        bytes: apk('1.0.0', 1),
        headers: {
          'X-Goog-Upload-Protocol': 'raw',
          'X-Goog-Upload-File-Name': 'a',
        },
      );

      expect(response.statusCode, 404);
    });

    test('answers 404 for an operation it does not know', () async {
      expect(
        (await call('GET', '/v1/$_app/releases/-/operations/nope')).statusCode,
        404,
      );
    });
  });

  group('releases', () {
    test('lists newest first, in pages', () async {
      final app = server.apps[_appId]!;
      for (var i = 1; i <= 3; i++) {
        server.addRelease(
          app,
          displayVersion: '1.0.$i',
          buildVersion: '$i',
          notes: i == 3 ? 'Newest' : null,
        );
      }

      final first = body(await call('GET', '/v1/$_app/releases?pageSize=2'));
      final second = body(
        await call('GET', '/v1/$_app/releases?pageSize=2&pageToken=2'),
      );

      expect(
        [
          for (final r in first['releases'] as List<dynamic>)
            (r as Map<String, dynamic>)['buildVersion'],
        ],
        ['3', '2'],
      );
      expect(at(first, ['releases', 0, 'releaseNotes', 'text']), 'Newest');
      expect(first['nextPageToken'], '2');
      expect(
        [
          for (final r in second['releases'] as List<dynamic>)
            (r as Map<String, dynamic>)['buildVersion'],
        ],
        ['1'],
      );
      expect(second['nextPageToken'], isNull);
    });

    test('lists nothing for an app without releases', () async {
      expect(body(await call('GET', '/v1/$_app/releases')), {
        'releases': <Object?>[],
      });
    });

    test('sets the release notes with the field mask', () async {
      server.pollsBeforeDone = 0;
      final release =
          at(body(await upload(apk('1.2.3', 45))), [
                'response',
                'release',
                'name',
              ])!
              as String;

      final patched = await call(
        'PATCH',
        '/v1/$release?updateMask=releaseNotes.text',
        json: {
          'releaseNotes': {'text': 'Fixes'},
        },
      );

      expect(patched.statusCode, 200);
      expect(at(body(patched), ['releaseNotes', 'text']), 'Fixes');
      expect(server.apps[_appId]!.releases.single.notes, 'Fixes');
    });

    test('refuses another mask and a body without text', () async {
      final release = server
          .addRelease(
            server.apps[_appId]!,
            displayVersion: '1',
            buildVersion: '1',
          )
          .name;

      expect(
        (await call('PATCH', '/v1/$release?updateMask=x', json: {})).statusCode,
        400,
      );
      expect(
        (await call(
          'PATCH',
          '/v1/$release?updateMask=releaseNotes.text',
          json: {'releaseNotes': <String, Object?>{}},
        )).statusCode,
        400,
      );
      expect(
        (await call(
          'PATCH',
          '/v1/$_app/releases/nope?updateMask=releaseNotes.text',
          json: {},
        )).statusCode,
        404,
      );
    });

    test('distributes to testers and groups that exist', () async {
      final release = server.addRelease(
        server.apps[_appId]!,
        displayVersion: '1',
        buildVersion: '1',
      );

      final response = await call(
        'POST',
        '/v1/${release.name}:distribute',
        json: {
          'testerEmails': ['a@example.com'],
          'groupAliases': ['qa'],
        },
      );
      await call('POST', '/v1/${release.name}:distribute', json: {});

      expect(response.statusCode, 200);
      expect(release.distributions, [
        'testers=a@example.com groups=qa',
        'testers= groups=',
      ]);
    });

    test('refuses a group that does not exist', () async {
      final release = server.addRelease(
        server.apps[_appId]!,
        displayVersion: '1',
        buildVersion: '1',
      );

      final response = await call(
        'POST',
        '/v1/${release.name}:distribute',
        json: {
          'groupAliases': ['nope'],
        },
      );

      expect(response.statusCode, 400);
      expect(
        at(body(response), ['error', 'message']),
        'Group nope does not exist.',
      );
    });
  });
}
