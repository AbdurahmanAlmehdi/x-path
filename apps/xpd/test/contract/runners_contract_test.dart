@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/runner_helpers.dart';
import '../helpers/test_engine.dart';

/// Every response of the runner endpoints, and every frame of the runner
/// protocol the engine sends, is checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late RunnerClient client;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => client = await RunnerClient.start());
  tearDown(() => client.close());

  void expectContract(
    RawResponse response, {
    required String path,
    required int status,
    String method = 'GET',
  }) {
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  test('request bodies match their schemas', () {
    expect(
      contract.validateSchema('CreatePairingTokenRequest', {'name': 'mac'}),
      isEmpty,
    );
    expect(
      contract.validateSchema('CreatePairingTokenRequest', {}),
      isNotEmpty,
    );
    expect(
      contract.validateSchema('PairRunnerRequest', {'pairingToken': 'xpp_x'}),
      isEmpty,
    );
    expect(
      contract.validateSchema('PairRunnerRequest', {'pairingToken': 1}),
      isNotEmpty,
    );
  });

  group('runners', () {
    test('GET list 200 and 401', () async {
      expectContract(
        await client.send('GET', '/runners'),
        path: '/runners',
        status: 200,
      );
      expectContract(
        await client.send('GET', '/runners', token: ''),
        path: '/runners',
        status: 401,
      );
    });

    test('POST pairing-tokens 201, 400, 401, 403 and 409', () async {
      expectContract(
        await client.send(
          'POST',
          '/runners/pairing-tokens',
          body: {'name': 'linux-box'},
        ),
        method: 'POST',
        path: '/runners/pairing-tokens',
        status: 201,
      );
      expectContract(
        await client.send('POST', '/runners/pairing-tokens', rawBody: '{}'),
        method: 'POST',
        path: '/runners/pairing-tokens',
        status: 400,
      );
      expectContract(
        await client.send(
          'POST',
          '/runners/pairing-tokens',
          token: '',
          body: {'name': 'a'},
        ),
        method: 'POST',
        path: '/runners/pairing-tokens',
        status: 401,
      );
      expectContract(
        await client.send(
          'POST',
          '/runners/pairing-tokens',
          kind: DeviceTokenKind.mcp,
          body: {'name': 'a'},
        ),
        method: 'POST',
        path: '/runners/pairing-tokens',
        status: 403,
      );
      expectContract(
        await client.send(
          'POST',
          '/runners/pairing-tokens',
          body: {'name': 'mac-mini'},
        ),
        method: 'POST',
        path: '/runners/pairing-tokens',
        status: 409,
      );
    });

    test('POST pair 201, 400, 401 and 409', () async {
      Future<String> token(String name) async => PairingToken.fromJson(
        (await client.send(
          'POST',
          '/runners/pairing-tokens',
          body: {'name': name},
        )).json,
      ).token;
      final first = await token('same');
      final second = await token('same');

      expectContract(
        await client.send(
          'POST',
          '/runners/pair',
          token: '',
          body: {'pairingToken': first},
        ),
        method: 'POST',
        path: '/runners/pair',
        status: 201,
      );
      expectContract(
        await client.send('POST', '/runners/pair', token: '', rawBody: '{}'),
        method: 'POST',
        path: '/runners/pair',
        status: 400,
      );
      expectContract(
        await client.send(
          'POST',
          '/runners/pair',
          token: '',
          body: {'pairingToken': 'xpp_nothing'},
        ),
        method: 'POST',
        path: '/runners/pair',
        status: 401,
      );
      expectContract(
        await client.send(
          'POST',
          '/runners/pair',
          token: '',
          body: {'pairingToken': second},
        ),
        method: 'POST',
        path: '/runners/pair',
        status: 409,
      );
    });

    test('POST revoke 200, 401, 403 and 404', () async {
      final path = '/runners/${client.runner.id}/revoke';

      expectContract(
        await client.send('POST', path, kind: DeviceTokenKind.mcp),
        method: 'POST',
        path: path,
        status: 403,
      );
      expectContract(
        await client.send('POST', path, token: ''),
        method: 'POST',
        path: path,
        status: 401,
      );
      expectContract(
        await client.send('POST', '/runners/rnr_nobody/revoke'),
        method: 'POST',
        path: '/runners/rnr_nobody/revoke',
        status: 404,
      );
      expectContract(
        await client.send('POST', path),
        method: 'POST',
        path: path,
        status: 200,
      );
    });

    test('GET connect 401, 403 and 426 before the upgrade', () async {
      expectContract(
        await client.engine.handshake('/runners/connect', token: ''),
        path: '/runners/connect',
        status: 401,
      );
      expectContract(
        await client.engine.handshake('/runners/connect'),
        path: '/runners/connect',
        status: 403,
      );
      expectContract(
        await client.engine.request(
          '/runners/connect',
          token: client.credential,
        ),
        path: '/runners/connect',
        status: 426,
      );
    });

    test('PUT artifact 201, 400, 401, 403 and 409', () async {
      final stream = await client.online();
      addTearDown(stream.close);
      final offer = await client.lease(stream);
      final bytes = utf8.encode('apk');
      final path = '/runners/jobs/${offer.jobId}/artifacts/a.apk';

      expectContract(
        await client.upload(
          offer.jobId,
          'a.apk',
          bytes,
          leaseId: offer.leaseId,
        ),
        method: 'PUT',
        path: path,
        status: 201,
      );
      expectContract(
        await client.upload(offer.jobId, 'a.apk', bytes),
        method: 'PUT',
        path: path,
        status: 400,
      );
      expectContract(
        await client.upload(
          offer.jobId,
          'a.apk',
          bytes,
          token: 'xpt_none',
          leaseId: offer.leaseId,
        ),
        method: 'PUT',
        path: path,
        status: 401,
      );
      expectContract(
        await client.upload(
          offer.jobId,
          'a.apk',
          bytes,
          token: client.secrets[DeviceTokenKind.mcp],
          leaseId: offer.leaseId,
        ),
        method: 'PUT',
        path: path,
        status: 403,
      );
      expectContract(
        await client.upload(offer.jobId, 'a.apk', bytes, leaseId: 'lse_wrong'),
        method: 'PUT',
        path: path,
        status: 409,
      );
    });
  });

  group('the protocol', () {
    test('every frame the engine sends matches its schema', () async {
      final stream = await client.engine.connectRunner(
        token: client.credential,
      );
      addTearDown(stream.close);
      final received = <EngineFrame>[];
      Future<T> take<T extends EngineFrame>() async {
        final frame = await stream.nextOf<T>();
        received.add(frame);
        return frame;
      }

      await take<WelcomeFrame>();
      stream.send(
        const HelloFrame(
          version: '1.0.0',
          os: 'macos',
          arch: 'arm64',
          cores: 8,
        ),
      );
      final probe = await take<ProbeFrame>();
      stream.send(
        ProbeResultFrame(probeId: probe.probeId, results: macProbeResults),
      );
      await client.waitOnline();
      final job = await client.engine.jobs.create(
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        steps: [
          StepPlan.of(
            const CommandStep(),
            const CommandInput(
              ProcessCommand('dart', secretFiles: {'F': 'ks'}),
            ),
          ),
        ],
      );
      await client.engine.credentialRepository.save(
        const CredentialRecord(
          id: 'crd_1',
          flavor: CredentialFlavor(
            id: 'flv_1',
            projectId: 'prj_1',
            appPath: '.',
            name: 'prod',
          ),
          kind: CredentialKind.keystore,
          secretKey: 'ks',
        ),
      );
      await client.engine.credentialSecrets.write('ks', 'bytes');
      await client.engine.runnerHub.offer(client.runner.id, job.id);
      final offer = await take<LeaseOfferFrame>();
      final lease = LeaseRef(jobId: offer.jobId, leaseId: offer.leaseId);
      stream
        ..send(HeartbeatFrame(leases: [lease]))
        ..send(
          LogChunkFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            seq: 2,
            lines: const [],
          ),
        )
        ..send(
          SecretRequestFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            key: 'ks',
          ),
        )
        ..send(
          SecretRequestFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            key: 'nope',
          ),
        )
        ..send(
          StepStateFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            ordinal: 0,
            state: StepState.succeeded,
            attempts: 1,
          ),
        )
        ..send(
          JobDoneFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            state: JobState.succeeded,
            lastChunk: 0,
          ),
        )
        ..send(
          const LeaseAcceptFrame(jobId: 'job_other', leaseId: 'lse_other'),
        );
      await take<HeartbeatAckFrame>();
      await take<ChunkAckFrame>();
      await take<SecretValueFrame>();
      await take<SecretDeniedFrame>();
      await take<DoneAckFrame>();
      await take<CancelFrame>();
      stream.sendText('{"type":"warp"}');
      await take<FaultFrame>();

      for (final frame in received) {
        expect(
          contract.validateSchema(
            'EngineFrame',
            jsonDecode(jsonEncode(frame.toJson())),
          ),
          isEmpty,
          reason: frame.type,
        );
      }
      expect(
        received.map((f) => f.type).toSet(),
        hasLength(received.length - 0),
      );
    });
  });
}
