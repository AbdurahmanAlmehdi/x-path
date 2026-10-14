import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../../helpers/runner_helpers.dart';
import '../../../helpers/test_engine.dart';

void main() {
  late RunnerClient client;

  setUp(() async => client = await RunnerClient.start());
  tearDown(() => client.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  Map<String, Object> pairingBody(String name) => {'name': name};

  group('POST /runners/pairing-tokens', () {
    test('answers 201 with a single-use token for 15 minutes', () async {
      final response = await client.send(
        'POST',
        '/runners/pairing-tokens',
        body: pairingBody('linux-box'),
      );

      expect(response.statusCode, 201);
      final token = PairingToken.fromJson(response.json);
      expect(token.token, startsWith('xpp_'));
      expect(token.name, 'linux-box');
      expect(
        token.expiresAt,
        client.engine.clock.now().add(const Duration(minutes: 15)),
      );
    });

    test('is for app and cli tokens', () async {
      final cli = await client.send(
        'POST',
        '/runners/pairing-tokens',
        kind: DeviceTokenKind.cli,
        body: pairingBody('a'),
      );
      expect(cli.statusCode, 201);

      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await client.send(
          'POST',
          '/runners/pairing-tokens',
          kind: kind,
          body: pairingBody('b'),
        );

        expect(response.statusCode, 403, reason: kind.name);
        expect(errorCode(response), 'forbidden');
      }
    });

    test('answers 400 for a body that is not usable', () async {
      for (final body in ['', 'not json', '[]', '{}', '{"name": 3}']) {
        final response = await client.send(
          'POST',
          '/runners/pairing-tokens',
          rawBody: body,
        );

        expect(response.statusCode, 400, reason: body);
        expect(errorCode(response), 'invalid_request');
      }
      final blank = await client.send(
        'POST',
        '/runners/pairing-tokens',
        body: pairingBody('  '),
      );
      expect(blank.statusCode, 400);
    });

    test('answers 409 for a name a runner has', () async {
      final response = await client.send(
        'POST',
        '/runners/pairing-tokens',
        body: pairingBody('mac-mini'),
      );

      expect(response.statusCode, 409);
      expect(errorCode(response), 'conflict');
    });

    test('answers 401 without a token', () async {
      final response = await client.send(
        'POST',
        '/runners/pairing-tokens',
        token: '',
        body: pairingBody('a'),
      );

      expect(response.statusCode, 401);
    });
  });

  group('POST /runners/pair', () {
    Future<String> pairingToken(String name) async {
      final response = await client.send(
        'POST',
        '/runners/pairing-tokens',
        body: pairingBody(name),
      );
      return PairingToken.fromJson(response.json).token;
    }

    test(
      'needs no bearer token and answers the runner and its credential',
      () async {
        final secret = await pairingToken('linux-box');

        final response = await client.send(
          'POST',
          '/runners/pair',
          token: '',
          body: {'pairingToken': secret},
        );

        expect(response.statusCode, 201);
        final paired = PairRunnerResponse.fromJson(response.json);
        expect(paired.runner.name, 'linux-box');
        expect(paired.runner.status, RunnerStatus.offline);
        expect(paired.token, startsWith('xpt_'));
        final credential = (await client.engine.tokens.authenticate(
          paired.token,
        ))!;
        expect(credential.kind, DeviceTokenKind.runner);
        expect(
          await client.engine.eventsOf<RunnerPaired>(),
          contains(RunnerPaired(runnerId: paired.runner.id, name: 'linux-box')),
        );
      },
    );

    test('works once', () async {
      final secret = await pairingToken('a');
      await client.send(
        'POST',
        '/runners/pair',
        token: '',
        body: {'pairingToken': secret},
      );

      final again = await client.send(
        'POST',
        '/runners/pair',
        token: '',
        body: {'pairingToken': secret},
      );

      expect(again.statusCode, 401);
      expect(errorCode(again), 'unauthorized');
      expect(again.json.toString(), contains('used already'));
      expect(again.headers['www-authenticate'], 'Bearer');
    });

    test('answers 401 for a token that expired or never was', () async {
      final secret = await pairingToken('a');
      client.engine.clock.advance(const Duration(minutes: 15));

      for (final token in [secret, 'xpp_nothing', 'junk']) {
        final response = await client.send(
          'POST',
          '/runners/pair',
          token: '',
          body: {'pairingToken': token},
        );

        expect(response.statusCode, 401, reason: token);
      }
    });

    test('answers 400 for a body that is not usable', () async {
      for (final body in ['', '{}', '{"pairingToken": 1}']) {
        final response = await client.send(
          'POST',
          '/runners/pair',
          token: '',
          rawBody: body,
        );

        expect(response.statusCode, 400, reason: body);
      }
    });

    test('answers 409 when the name was taken meanwhile', () async {
      final first = await pairingToken('same');
      final second = await pairingToken('same');
      await client.send(
        'POST',
        '/runners/pair',
        token: '',
        body: {'pairingToken': first},
      );

      final response = await client.send(
        'POST',
        '/runners/pair',
        token: '',
        body: {'pairingToken': second},
      );

      expect(response.statusCode, 409);
    });
  });

  group('GET /runners', () {
    test('lists the runners with where they are', () async {
      final stream = await client.online();
      addTearDown(stream.close);

      final response = await client.send('GET', '/runners');

      expect(response.statusCode, 200);
      final runner = RunnersResponse.fromJson(response.json).runners.single;
      expect(runner.id, client.runner.id);
      expect(runner.status, RunnerStatus.online);
      expect(runner.capabilities, ['flutter', 'ios-sign']);
      expect(runner.slots, 2);
      expect(runner.os, 'macos');
      expect(runner.cores, 8);
    });

    test('is open to an app, a cli and an mcp token, not a runner', () async {
      for (final kind in DeviceTokenKind.values) {
        final response = await client.send('GET', '/runners', kind: kind);

        expect(
          response.statusCode,
          kind == DeviceTokenKind.runner ? 403 : 200,
          reason: kind.name,
        );
      }
    });
  });

  group('POST /runners/{id}/revoke', () {
    test('revokes the runner and its credential', () async {
      final stream = await client.online();
      addTearDown(stream.close);

      final response = await client.send(
        'POST',
        '/runners/${client.runner.id}/revoke',
      );

      expect(response.statusCode, 200);
      final runner = Runner.fromJson(response.json);
      expect(runner.status, RunnerStatus.revoked);
      expect(runner.revokedAt, isNotNull);
      expect(await stream.closeCode(), runnerRevokedCloseCode);
      final connect = await client.engine.handshake(
        '/runners/connect',
        token: client.credential,
      );
      expect(connect.statusCode, 401);
    });

    test('is for app and cli tokens', () async {
      final cli = await client.send(
        'POST',
        '/runners/${client.runner.id}/revoke',
        kind: DeviceTokenKind.cli,
      );
      expect(cli.statusCode, 200);

      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await client.send(
          'POST',
          '/runners/${client.runner.id}/revoke',
          kind: kind,
        );

        expect(response.statusCode, 403, reason: kind.name);
      }
    });

    test('answers 404 for a runner that does not exist', () async {
      final response = await client.send('POST', '/runners/rnr_nobody/revoke');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });
  });

  group('PUT /runners/jobs/{id}/artifacts/{name}', () {
    final bytes = utf8.encode('the apk');

    test('stores a file that is what the runner declared', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);

      final response = await client.upload(
        offer.jobId,
        'dev-1.0.0+7.apk',
        bytes,
        leaseId: offer.leaseId,
      );

      expect(response.statusCode, 201);
      final artifact = Artifact.fromJson(response.json);
      expect(artifact.jobId, offer.jobId);
      expect(artifact.kind, ArtifactKind.apk);
      expect(artifact.name, 'dev-1.0.0+7.apk');
      expect(artifact.size, bytes.length);
      expect(artifact.sha256, sha256.convert(bytes).toString());
      expect(
        client.engine.artifactStore.files['${offer.jobId}/dev-1.0.0+7.apk'],
        bytes,
      );
    });

    test('rejects a file whose digest is not the declared one', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);

      final wrongDigest = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
        sha256Hex: sha256.convert([1]).toString(),
      );

      expect(wrongDigest.statusCode, 400);
      expect(errorCode(wrongDigest), 'invalid_request');
      expect(wrongDigest.json.toString(), contains('SHA-256'));
      expect(client.engine.artifactStore.files, isEmpty);
    });

    test('answers 400 for what is missing or not valid', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);

      final noLease = await client.upload(offer.jobId, 'a.apk', bytes);
      final noDigest = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
        sha256Hex: '',
      );
      final noKind = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
        kind: null,
      );
      final badKind = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
        kind: 'zip',
      );
      final chunked = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
        chunked: true,
      );
      final badName = await client.upload(
        offer.jobId,
        '.hidden',
        bytes,
        leaseId: offer.leaseId,
      );

      for (final response in [
        noLease,
        noDigest,
        noKind,
        badKind,
        chunked,
        badName,
      ]) {
        expect(response.statusCode, 400, reason: response.body);
        expect(errorCode(response), 'invalid_request');
      }
      expect(noLease.json.toString(), contains('x-lease-id'));
      expect(chunked.json.toString(), contains('Content-Length'));
    });

    test('answers 409 for a lease the runner does not hold', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);

      final wrong = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        leaseId: 'lse_wrong',
      );
      final unknownJob = await client.upload(
        'job_nobody',
        'a.apk',
        bytes,
        leaseId: offer.leaseId,
      );

      expect(wrong.statusCode, 409);
      expect(errorCode(wrong), 'conflict');
      expect(unknownJob.statusCode, 409);
      expect(client.engine.artifactStore.files, isEmpty);
    });

    test('is for the runner token of a runner', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);

      for (final kind in [
        DeviceTokenKind.app,
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
      ]) {
        final response = await client.upload(
          offer.jobId,
          'a.apk',
          bytes,
          token: client.secrets[kind],
          leaseId: offer.leaseId,
        );

        expect(response.statusCode, 403, reason: kind.name);
      }
      // A runner token that belongs to no runner.
      final stray = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        token: client.secrets[DeviceTokenKind.runner],
        leaseId: offer.leaseId,
      );
      expect(stray.statusCode, 403);
      final none = await client.upload(
        offer.jobId,
        'a.apk',
        bytes,
        token: 'xpt_none',
        leaseId: offer.leaseId,
      );
      expect(none.statusCode, 401);
    });
  });
}
