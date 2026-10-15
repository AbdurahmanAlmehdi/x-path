import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../helpers/fake_engine.dart';
import '../helpers/samples.dart' as sample;
import '../helpers/scripted_connector.dart';

void main() {
  late FakeEngine engine;
  late XpClient client;

  setUp(() async {
    engine = await FakeEngine.start();
    client = XpClient(baseUrl: engine.url, token: 'xp_secret');
  });

  tearDown(() async {
    client.close();
    await engine.close();
  });

  group('listRunners', () {
    test('reads the runners', () async {
      engine.json('GET', '/runners', RunnersResponse([sample.runner]).toJson());

      expect(await client.listRunners(), [sample.runner]);
      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
    });
  });

  group('downloadRunnerBundle', () {
    test('asks for the bundle of the machine and reads the digest', () async {
      engine.on('GET', '/runners/bundle', (request, _) {
        request.response
          ..headers.set('X-Content-SHA256', 'ABC')
          ..headers.contentLength = 3
          ..add([1, 2, 3]);
        return request.response.close();
      });

      final download = await client.downloadRunnerBundle(
        os: 'linux',
        arch: 'arm64',
      );

      expect(engine.last.query, {'os': 'linux', 'arch': 'arm64'});
      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
      expect(download.sha256, 'abc');
      expect(download.length, 3);
      expect(await download.content.expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
    });

    test('a missing bundle is an ApiException', () async {
      engine.error(
        'GET',
        '/runners/bundle',
        ApiErrorCode.notFound,
        'No bundle for linux-arm64.',
      );

      await expectLater(
        client.downloadRunnerBundle(os: 'linux', arch: 'arm64'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('No bundle'),
          ),
        ),
      );
    });
  });

  group('createPairingToken', () {
    test('asks for a token for the runner called so', () async {
      final token = PairingToken(
        token: 'xpp_secret',
        name: 'mac-mini',
        expiresAt: sample.at,
      );
      engine.json(
        'POST',
        '/runners/pairing-tokens',
        token.toJson(),
        status: 201,
      );

      expect(await client.createPairingToken('mac-mini'), token);
      expect(engine.last.json, {'name': 'mac-mini'});
      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
    });

    test('a refusal is an ApiException', () async {
      engine.error(
        'POST',
        '/runners/pairing-tokens',
        ApiErrorCode.forbidden,
        'An mcp token cannot pair a runner.',
      );

      await expectLater(
        client.createPairingToken('x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });
  });

  group('pairRunner', () {
    test('exchanges the pairing token and sends no bearer token', () async {
      final paired = PairRunnerResponse(
        runner: sample.runner,
        token: 'xpt_new',
      );
      engine.json('POST', '/runners/pair', paired.toJson(), status: 201);

      expect(await client.pairRunner('xpp_secret'), paired);
      expect(engine.last.json, {'pairingToken': 'xpp_secret'});
      expect(engine.last.headers, isNot(contains('authorization')));
    });

    test('a pairing token that is refused is an ApiException', () async {
      engine.error(
        'POST',
        '/runners/pair',
        ApiErrorCode.unauthorized,
        'This pairing token expired.',
      );

      await expectLater(
        client.pairRunner('xpp_old'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.unauthorized,
          ),
        ),
      );
    });
  });

  group('revokeRunner', () {
    test('revokes by id', () async {
      engine.json('POST', '/runners/rnr_1/revoke', sample.runner.toJson());

      expect(await client.revokeRunner('rnr_1'), sample.runner);
      expect(engine.last.method, 'POST');
    });
  });

  group('connectRunner', () {
    test('opens the runner socket with the credential', () async {
      final connector = ScriptedConnector();
      final socket = connector.socket();
      Map<String, String>? sent;
      final runner = XpClient(
        baseUrl: Uri.parse('http://engine:7480'),
        token: 'xpt_runner',
        connector: (uri, headers) {
          sent = headers;
          return connector.call(uri, headers);
        },
      );
      addTearDown(runner.close);

      final channel = await runner.connectRunner();

      expect(identical(channel, socket), isTrue);
      expect(
        connector.uris.single.toString(),
        'ws://engine:7480/runners/connect',
      );
      expect(sent!['authorization'], 'Bearer xpt_runner');
    });

    test('a refusal is thrown', () async {
      final connector = ScriptedConnector()
        ..fail(const ApiException('No.', statusCode: 403));
      final runner = XpClient(
        baseUrl: Uri.parse('http://engine:7480'),
        token: 'xp_secret',
        connector: connector.call,
      );
      addTearDown(runner.close);

      await expectLater(runner.connectRunner(), throwsA(isA<ApiException>()));
    });
  });

  group('uploadRunnerArtifact', () {
    final bytes = utf8.encode('the apk');

    Future<void> echo(HttpRequest request, Call call) {
      request.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(sample.artifact.toJson()));
      return request.response.close();
    }

    test(
      'sends the file with what it declares and reads the artifact',
      () async {
        engine.on('PUT', '/runners/jobs/job_1/artifacts/app.apk', echo);

        final artifact = await client.uploadRunnerArtifact(
          jobId: 'job_1',
          name: 'app.apk',
          leaseId: 'lse_1',
          kind: ArtifactKind.apk,
          content: Stream.fromIterable([bytes.sublist(0, 3), bytes.sublist(3)]),
          size: bytes.length,
          sha256: 'a' * 64,
        );

        expect(artifact, sample.artifact);
        final call = engine.last;
        expect(call.body, 'the apk');
        expect(call.query, {'kind': 'apk'});
        expect(call.headers['authorization'], 'Bearer xp_secret');
        expect(call.headers['x-content-sha256'], 'a' * 64);
        expect(call.headers['x-lease-id'], 'lse_1');
        expect(call.headers['content-length'], '${bytes.length}');
        expect(call.headers['content-type'], 'application/octet-stream');
      },
    );

    test('a refusal is an ApiException', () async {
      engine.error(
        'PUT',
        '/runners/jobs/job_1/artifacts/app.apk',
        ApiErrorCode.conflict,
        'Runner rnr_1 does not hold lease lse_1.',
      );

      await expectLater(
        client.uploadRunnerArtifact(
          jobId: 'job_1',
          name: 'app.apk',
          leaseId: 'lse_1',
          kind: ArtifactKind.apk,
          content: Stream.value(bytes),
          size: bytes.length,
          sha256: 'a' * 64,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.conflict,
          ),
        ),
      );
    });

    test('a source that fails ends the upload', () async {
      engine.on('PUT', '/runners/jobs/job_1/artifacts/app.apk', echo);

      await expectLater(
        client.uploadRunnerArtifact(
          jobId: 'job_1',
          name: 'app.apk',
          leaseId: 'lse_1',
          kind: ArtifactKind.apk,
          content: Stream<List<int>>.multi((controller) {
            controller
              ..add(bytes.sublist(0, 2))
              ..addError(StateError('disk on fire'));
          }),
          size: bytes.length,
          sha256: 'a' * 64,
        ),
        throwsA(isA<ConnectionException>()),
      );
    });

    test('gives up on an engine that never answers', () async {
      engine.on('PUT', '/runners/jobs/job_1/artifacts/app.apk', (_, _) {
        return Completer<void>().future;
      });

      await expectLater(
        client.uploadRunnerArtifact(
          jobId: 'job_1',
          name: 'app.apk',
          leaseId: 'lse_1',
          kind: ArtifactKind.apk,
          content: Stream.value(bytes),
          size: bytes.length,
          sha256: 'a' * 64,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.message,
            'message',
            contains('did not answer'),
          ),
        ),
      );
    });
  });
}
