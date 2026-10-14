import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/runner_helpers.dart';
import '../../../helpers/test_engine.dart';

void main() {
  late RunnerClient client;

  setUp(() async => client = await RunnerClient.start());
  tearDown(() => client.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  group('before the upgrade', () {
    test('answers 401 without a token or with a wrong one', () async {
      for (final token in ['', 'xpt_wrong']) {
        final response = await client.engine.handshake(
          '/runners/connect',
          token: token,
        );

        expect(response.statusCode, 401, reason: token);
      }
    });

    test('answers 426 for a plain request', () async {
      final response = await client.engine.request(
        '/runners/connect',
        token: client.credential,
      );

      expect(response.statusCode, 426);
      expect(errorCode(response), 'upgrade_required');
    });

    test('answers 403 for a token that is not a runner credential', () async {
      for (final kind in DeviceTokenKind.values) {
        final response = await client.engine.handshake(
          '/runners/connect',
          token: client.secrets[kind],
        );

        expect(response.statusCode, 403, reason: kind.name);
        expect(errorCode(response), 'forbidden');
      }
    });

    test('refuses a browser origin', () async {
      final response = await client.engine.request(
        '/runners/connect',
        token: client.credential,
        headers: {
          'connection': 'Upgrade',
          'upgrade': 'websocket',
          'sec-websocket-version': '13',
          'sec-websocket-key': 'AQEBAQEBAQEBAQEBAQEBAQ==',
          'origin': 'http://evil.example',
        },
      );

      expect(response.statusCode, 403);
    });
  });

  group('the connection', () {
    test('starts with the welcome and a probe after hello', () async {
      final stream = await client.engine.connectRunner(
        token: client.credential,
      );
      addTearDown(stream.close);

      final welcome = await stream.next();
      expect(
        welcome,
        WelcomeFrame(
          runnerId: client.runner.id,
          engineVersion: '9.9.9',
          apiVersion: apiVersion,
        ),
      );
      stream.send(
        const HelloFrame(
          version: '1.0.0',
          os: 'macos',
          arch: 'arm64',
          cores: 8,
        ),
      );
      final probe = await stream.nextOf<ProbeFrame>();
      expect(probe.commands, const RunnerProbe().commands);
    });

    test('makes the runner online once it answered the probe', () async {
      final stream = await client.online();
      addTearDown(stream.close);

      expect(
        (await client.engine.runnerService.get(client.runner.id)).status,
        RunnerStatus.online,
      );
      expect(await client.engine.eventsOf<RunnerConnected>(), [
        RunnerConnected(
          runnerId: client.runner.id,
          name: 'mac-mini',
          capabilities: const ['flutter', 'ios-sign'],
          slots: 2,
        ),
      ]);
    });

    test('leases a job and takes its report, over the socket', () async {
      final stream = await client.online();
      addTearDown(stream.close);

      final offer = await client.lease(stream);
      final lease = LeaseRef(jobId: offer.jobId, leaseId: offer.leaseId);
      stream
        ..send(LeaseAcceptFrame(jobId: lease.jobId, leaseId: lease.leaseId))
        ..send(HeartbeatFrame(leases: [lease]))
        ..send(
          LogChunkFrame(
            jobId: lease.jobId,
            leaseId: lease.leaseId,
            seq: 1,
            lines: [
              ChunkLine(
                step: 0,
                at: DateTime.utc(2026, 10, 14),
                stream: LogStream.stdout,
                text: 'building',
              ),
            ],
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
        );
      final ack = await stream.nextOf<ChunkAckFrame>();
      stream.send(
        JobDoneFrame(
          jobId: lease.jobId,
          leaseId: lease.leaseId,
          state: JobState.succeeded,
          lastChunk: 1,
        ),
      );
      final done = await stream.nextOf<DoneAckFrame>();

      expect(ack.status, ChunkStatus.stored);
      expect(done.state, JobState.succeeded);
      final job = await client.engine.jobs.get(offer.jobId);
      expect(job.state, JobState.succeeded);
      expect(job.runnerId, client.runner.id);
      expect(
        client.engine.logStore.read(offer.jobId).map((l) => l.text),
        emits('building'),
      );
    });

    test(
      'answers a frame it cannot read, and ends on text that is no frame',
      () async {
        final stream = await client.engine.connectRunner(
          token: client.credential,
        );
        addTearDown(stream.close);
        await stream.next();

        stream.sendText('{"type":"hello"}');
        final fault = await stream.nextOf<FaultFrame>();
        stream.sendText('not json');

        expect(fault.code, 'invalid_frame');
        expect(await stream.closeCode(), runnerProtocolCloseCode);
      },
    );

    test('ends on a binary frame', () async {
      final stream = await client.engine.connectRunner(
        token: client.credential,
      );
      addTearDown(stream.close);
      await stream.next();

      stream.socket.add([1, 2, 3]);

      expect(await stream.closeCode(), runnerProtocolCloseCode);
    });

    test('is replaced by a newer connection of the runner', () async {
      final first = await client.online();
      addTearDown(first.close);
      final second = await client.engine.connectRunner(
        token: client.credential,
      );
      addTearDown(second.close);

      expect(await first.closeCode(), runnerReplacedCloseCode);
      await second.nextOf<WelcomeFrame>();
      expect(client.engine.runnerHub.isConnected(client.runner.id), isTrue);
    });

    test('ends the runner when the socket closes', () async {
      final stream = await client.online();
      await stream.close();

      for (var i = 0; i < 200; i++) {
        if (!client.engine.runnerHub.isConnected(client.runner.id)) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(client.engine.runnerHub.isConnected(client.runner.id), isFalse);
      expect(
        (await client.engine.runnerService.get(client.runner.id)).status,
        RunnerStatus.offline,
      );
      expect(await client.engine.eventsOf<RunnerDisconnected>(), hasLength(1));
    });

    test('is closed with 1000 when the engine shuts down', () async {
      final stream = await client.online();
      addTearDown(stream.close);

      await client.engine.close();

      expect(await stream.closeCode(), 1000);
    });
  });
}
