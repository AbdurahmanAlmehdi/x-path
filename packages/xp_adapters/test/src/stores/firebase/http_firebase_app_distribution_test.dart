import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

const _projectNumber = '684690133351';
const _appId = '1:684690133351:android:b434734f585770367c1fc2';
const _app = 'projects/$_projectNumber/apps/$_appId';

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
  late FakeFirebaseServer server;
  late FakeFirebaseApp app;
  late List<Duration> sleeps;

  PlayServiceAccount accountOf(FakeFirebaseServer server) =>
      PlayServiceAccount.fromSecret(server.serviceAccountJson());

  HttpFirebaseAppDistribution firebase({
    http.Client? client,
    Uri? baseUrl,
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 60),
    PlayServiceAccount? account,
  }) {
    final created = HttpFirebaseAppDistribution(
      account: account ?? accountOf(server),
      clock: clock,
      client: client,
      baseUrl: baseUrl ?? server.baseUrl,
      maxAttempts: maxAttempts,
      timeout: timeout,
      sleep: (duration) async => sleeps.add(duration),
    );
    addTearDown(created.close);
    return created;
  }

  Future<Object?> failure(Future<Object?> future) =>
      future.then<Object?>((_) => null, onError: (Object e) => e);

  List<int> apk(String name, int code, {int padding = 0}) =>
      fakeBinary('apk', versionName: name, versionCode: code, padding: padding);

  Future<FirebaseOperation> upload(
    HttpFirebaseAppDistribution client,
    List<int> bytes,
  ) => client.uploadRelease(
    _app,
    content: () => Stream.fromIterable([bytes]),
    length: bytes.length,
    fileName: 'dev 1.2.3+45.apk',
  );

  /// The requests the API (not the token endpoint) received.
  Iterable<FakeFirebaseRequest> api() =>
      server.requests.where((r) => r.uri.path != '/token');

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    sleeps = [];
    server = await FakeFirebaseServer.start(now: clock.now);
    addTearDown(server.close);
    app = server.addApp(_projectNumber, _appId, groups: {'qa'});
  });

  group('the access token', () {
    test('is a valid bearer token on every call', () async {
      final client = firebase();

      await client.releases(_app);
      await client.releases(_app);

      expect(api().map((r) => r.tokenProblem), [null, null]);
      expect(server.tokensIssued, 1);
    });

    test('is asked for with the cloud-platform scope', () async {
      await firebase().verifyAccess();

      expect(server.tokensIssued, 1);
    });

    test('is refused with a fix when the key is not registered', () async {
      final client = firebase(
        account: PlayServiceAccount.fromSecret(
          server.serviceAccountJson(privateKeyPem: fakePlayOtherPrivateKeyPem),
        ),
      );

      final error = await failure(client.verifyAccess());

      expect(error, isA<FirebaseAuthException>());
      expect((error! as FirebaseAuthException).reason, 'invalid_grant');
      expect((error as FirebaseAuthException).fix, contains('service account'));
      expect(api(), isEmpty);
    });

    test('is renewed after a 401 and the call is repeated once', () async {
      final client = firebase();
      await client.releases(_app);

      server.revokeTokens();
      await client.releases(_app);

      expect(server.tokensIssued, 2);
    });

    test('is not renewed twice for the same call', () async {
      final client = firebase();
      await client.releases(_app);
      server
        ..revokeTokens()
        ..failNext(401, message: 'Still no');

      final error = await failure(client.releases(_app));

      expect(error, isA<FirebaseAuthException>());
    });

    test('cannot be fetched from an endpoint that is down', () async {
      final unreachable = firebase(
        account: PlayServiceAccount.fromSecret(
          jsonEncode({
            'client_email': 'a@b.iam.gserviceaccount.com',
            'private_key': fakePlayPrivateKeyPem,
            'token_uri': 'http://localhost:1/token',
          }),
        ),
      );

      final error = await failure(unreachable.verifyAccess());

      expect(error, isA<FirebaseServerException>());
      expect((error! as FirebaseServerException).statusCode, 0);
    });
  });

  group('uploadRelease', () {
    test(
      'sends the raw bytes with the upload headers and the length',
      () async {
        final bytes = apk('1.2.3', 45, padding: 100);

        final operation = await upload(firebase(), bytes);

        final request = api().single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/upload/v1/$_app/releases:upload');
        expect(request.headers['x-goog-upload-protocol'], 'raw');
        expect(
          request.headers['x-goog-upload-file-name'],
          'dev%201.2.3%2B45.apk',
        );
        expect(request.headers['content-type'], 'application/octet-stream');
        expect(request.bodyLength, bytes.length);
        expect(operation.done, isFalse);
        expect(operation.name, startsWith('$_app/releases/-/operations/'));
      },
    );

    test('reads the release of an operation that is done at once', () async {
      server.pollsBeforeDone = 0;

      final operation = await upload(firebase(), apk('1.2.3', 45));

      expect(operation.done, isTrue);
      expect(operation.result, FirebaseUploadResult.created);
      expect(operation.release?.displayVersion, '1.2.3');
      expect(operation.release?.buildVersion, '45');
      expect(operation.release?.name, startsWith('$_app/releases/'));
      expect(operation.release?.firebaseConsoleUri, isNotNull);
      expect(operation.release?.testingUri, isNotNull);
    });

    test('is polled until done', () async {
      final client = firebase();
      final started = await upload(client, apk('1.2.3', 45));

      final polled = await client.operation(started.name);

      expect(polled.done, isTrue);
      expect(polled.release?.buildVersion, '45');
    });

    test('is not repeated after a server error', () async {
      server.failNext(503, pathContains: 'releases:upload');

      final error = await failure(upload(firebase(), apk('1.2.3', 45)));

      expect(error, isA<FirebaseServerException>());
      expect(api(), hasLength(1));
      expect(sleeps, isEmpty);
    });

    test('says what Firebase refuses about the binary', () async {
      final error = await failure(upload(firebase(), utf8.encode('nope')));

      expect(error, isA<FirebaseValidationException>());
      expect((error! as FirebaseValidationException).message, contains('APK'));
      expect((error as FirebaseException).reason, 'INVALID_ARGUMENT');
    });

    test('reads the error of a failed operation', () async {
      final client = firebase(
        client: _mock(
          (request) => http.Response(
            jsonEncode({
              'name': '$_app/releases/-/operations/o1',
              'done': true,
              'error': {'code': 3, 'message': 'Invalid APK'},
            }),
            200,
          ),
        ),
      );

      final operation = await client.operation(
        '$_app/releases/-/operations/o1',
      );

      expect(operation.error, 'Invalid APK');
      expect(operation.release, isNull);
    });

    test('has a default message for an error without one', () async {
      final client = firebase(
        client: _mock(
          (request) => http.Response(
            jsonEncode({
              'name': 'o',
              'done': true,
              'error': <String, Object?>{},
            }),
            200,
          ),
        ),
      );

      expect((await client.operation('o')).error, 'The upload failed.');
    });

    test('refuses an answer without an operation name', () async {
      final client = firebase(
        client: _mock((request) => http.Response('{}', 200)),
      );

      expect(
        await failure(client.operation('x')),
        isA<FirebaseServerException>(),
      );
    });

    test('refuses a release without a name', () async {
      final client = firebase(
        client: _mock(
          (request) => http.Response(
            jsonEncode({
              'name': 'o',
              'done': true,
              'response': {
                'release': {'buildVersion': '1'},
              },
            }),
            200,
          ),
        ),
      );

      expect(
        await failure(client.operation('o')),
        isA<FirebaseServerException>(),
      );
    });

    test('times out when the upload hangs', () async {
      final client = firebase(
        client: MockClient.streaming((request, body) async {
          if (request.url.path == '/token') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"access_token": "t"}')),
              200,
            );
          }
          return await Completer<http.StreamedResponse>().future;
        }),
        timeout: const Duration(milliseconds: 20),
      );

      final error = await failure(client.releases(_app));

      expect(error, isA<FirebaseServerException>());
      expect((error! as FirebaseServerException).message, contains('in time'));
    });

    test('says so when Firebase cannot be reached', () async {
      final client = firebase(
        client: MockClient.streaming((request, body) async {
          if (request.url.path == '/token') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"access_token": "t"}')),
              200,
            );
          }
          throw http.ClientException('connection refused');
        }),
      );

      final error = await failure(client.releases(_app));

      expect(error, isA<FirebaseServerException>());
      expect(
        (error! as FirebaseServerException).message,
        contains('reachable'),
      );
    });
  });

  group('releases', () {
    test('lists the newest first with their versions and notes', () async {
      server
        ..addRelease(app, displayVersion: '1.0.0', buildVersion: '1')
        ..addRelease(
          app,
          displayVersion: '1.1.0',
          buildVersion: '2',
          notes: 'New',
        );

      final releases = await firebase().releases(_app);

      expect([for (final r in releases) r.buildVersion], ['2', '1']);
      expect(releases.first.releaseNotes, 'New');
      expect(releases.first.displayVersion, '1.1.0');
      final request = api().single;
      expect(request.uri.queryParameters['orderBy'], 'createTime desc');
      expect(request.uri.queryParameters['pageSize'], '100');
    });

    test('reads the pages it is asked for, no more', () async {
      for (var i = 1; i <= 250; i++) {
        server.addRelease(app, displayVersion: '1.0.0', buildVersion: '$i');
      }

      final one = await firebase().releases(_app);
      final three = await firebase().releases(_app, pages: 3);
      final many = await firebase().releases(_app, pages: 10);

      expect(one, hasLength(100));
      expect(three, hasLength(250));
      expect(many, hasLength(250));
    });

    test('is empty for an app without releases', () async {
      expect(await firebase().releases(_app), isEmpty);
    });

    test('retries a server error and waits out a throttle', () async {
      server
        ..failNext(503)
        ..rateLimitNext(1, retryAfterSeconds: 4);

      await firebase().releases(_app);

      expect(sleeps, [const Duration(seconds: 4), const Duration(seconds: 2)]);
    });

    test('gives up on a throttle that asks for a long wait', () async {
      server.rateLimitNext(1, retryAfterSeconds: 3600);

      final error = await failure(firebase().releases(_app));

      expect(error, isA<FirebaseRateLimitedException>());
      expect(
        (error! as FirebaseRateLimitedException).retryAfter,
        const Duration(hours: 1),
      );
      expect(sleeps, isEmpty);
    });

    test('gives up after the attempts it has', () async {
      server
        ..failNext(503)
        ..failNext(503)
        ..failNext(503);

      final error = await failure(firebase(maxAttempts: 2).releases(_app));

      expect(error, isA<FirebaseServerException>());
      expect(sleeps, hasLength(1));
    });
  });

  group('release notes and distribution', () {
    late FakeFirebaseRelease release;

    setUp(() {
      release = server.addRelease(
        app,
        displayVersion: '1.2.3',
        buildVersion: '45',
      );
    });

    test('sets the notes with the field mask', () async {
      final updated = await firebase().updateReleaseNotes(
        release.name,
        'Fixes',
      );

      expect(updated.releaseNotes, 'Fixes');
      expect(release.notes, 'Fixes');
      final request = api().single;
      expect(request.method, 'PATCH');
      expect(request.uri.queryParameters['updateMask'], 'releaseNotes.text');
      expect(request.body, {
        'releaseNotes': {'text': 'Fixes'},
      });
    });

    test('distributes to testers and groups', () async {
      await firebase().distribute(
        release.name,
        testerEmails: ['a@example.com'],
        groupAliases: ['qa'],
      );

      expect(release.distributions, ['testers=a@example.com groups=qa']);
      expect(api().single.body, {
        'testerEmails': ['a@example.com'],
        'groupAliases': ['qa'],
      });
    });

    test('sends an empty body when it distributes to nobody', () async {
      await firebase().distribute(release.name);

      expect(api().single.body, <String, Object?>{});
    });

    test('says a group does not exist', () async {
      final error = await failure(
        firebase().distribute(release.name, groupAliases: ['nope']),
      );

      expect(error, isA<FirebaseValidationException>());
      expect((error! as FirebaseValidationException).message, contains('nope'));
    });

    test('retries a server error of a repeatable call', () async {
      server.failNext(500, method: 'POST');

      await firebase().distribute(release.name, groupAliases: ['qa']);

      expect(release.distributions, hasLength(1));
      expect(sleeps, [const Duration(seconds: 1)]);
    });
  });

  group('errors', () {
    test('are typed by status, with the status name of Google', () async {
      server.apps[_appId]!.allowedAccounts = {'someone@else'};

      final forbidden = await failure(firebase().releases(_app));

      expect(forbidden, isA<FirebaseForbiddenException>());
      expect(
        (forbidden! as FirebaseForbiddenException).reason,
        'PERMISSION_DENIED',
      );
      expect(
        (forbidden as FirebaseException).fix,
        contains('Firebase App Distribution Admin'),
      );

      final missing = await failure(
        firebase().releases('projects/$_projectNumber/apps/1:1:android:zz'),
      );
      expect(missing, isA<FirebaseNotFoundException>());
    });

    test('keep a message when the body is not Google error JSON', () async {
      final client = firebase(
        client: _mock((request) => http.Response('<html>', 502)),
      );

      final error = await failure(client.releases(_app));

      expect(error, isA<FirebaseServerException>());
      expect((error! as FirebaseServerException).message, contains('HTTP 502'));
    });

    test('say so when a success is not a JSON object', () async {
      final client = firebase(
        client: _mock((request) => http.Response('[1]', 200)),
      );

      expect(
        await failure(client.releases(_app)),
        isA<FirebaseServerException>(),
      );
    });

    test('accept an empty success', () async {
      final client = firebase(
        client: _mock((request) => http.Response('', 200)),
      );

      expect(await client.releases(_app), isEmpty);
    });

    test('use a default message for an error body without one', () async {
      final client = firebase(
        client: _mock(
          (request) =>
              http.Response(jsonEncode({'error': <String, Object?>{}}), 418),
        ),
      );

      final error = await failure(client.releases(_app));

      expect(error, isA<FirebaseValidationException>());
      expect(
        (error! as FirebaseValidationException).message,
        'Firebase App Distribution refused.',
      );
    });
  });
}
