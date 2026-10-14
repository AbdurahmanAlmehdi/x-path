import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 14, 9, 30);
  const lease = LeaseRef(jobId: 'job_1', leaseId: 'lse_1');

  /// A frame goes through real JSON text, as it does on the socket.
  Map<String, dynamic> wire(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  group('RunnerFrame', () {
    final frames = <RunnerFrame>[
      const HelloFrame(version: '1.0.0', os: 'macos', arch: 'arm64', cores: 8),
      const HelloFrame(
        version: '1.0.0',
        os: 'linux',
        arch: 'x64',
        cores: 16,
        maxJobs: 2,
        draining: true,
        leases: [lease],
      ),
      const ProbeResultFrame(
        probeId: 'prb_1',
        results: [
          ProbeResult(
            id: 'git',
            status: ProbeStatus.exited,
            exitCode: 0,
            stdout: 'git version 2.50.1\n',
          ),
          ProbeResult(id: 'swift', status: ProbeStatus.notStarted),
          ProbeResult(id: 'xcodebuild', status: ProbeStatus.skipped),
          ProbeResult(id: 'slow', status: ProbeStatus.timedOut, stderr: 'x'),
        ],
      ),
      const LeaseAcceptFrame(jobId: 'job_1', leaseId: 'lse_1'),
      const LeaseRejectFrame(jobId: 'job_1', leaseId: 'lse_1', reason: 'busy'),
      const HeartbeatFrame(),
      const HeartbeatFrame(leases: [lease]),
      LogChunkFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        seq: 3,
        lines: [
          ChunkLine(step: 1, at: at, stream: LogStream.stderr, text: 'warning'),
        ],
      ),
      const StepStateFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        ordinal: 0,
        state: StepState.running,
        attempts: 1,
      ),
      StepStateFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        ordinal: 0,
        state: StepState.succeeded,
        attempts: 2,
        result: const {'artifact': 'a.apk'},
        message: 'done',
        startedAt: at,
        finishedAt: at.add(const Duration(seconds: 5)),
      ),
      const JobDoneFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.succeeded,
        lastChunk: 4,
      ),
      const JobDoneFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.failed,
        lastChunk: 0,
        message: 'Step 1 failed.',
      ),
      const SecretRequestFrame(jobId: 'job_1', leaseId: 'lse_1', key: 'k'),
      const DrainFrame(),
      const DrainFrame(draining: false),
    ];

    test('round-trips every frame through JSON', () {
      for (final frame in frames) {
        expect(RunnerFrame.fromJson(wire(frame.toJson())), frame);
        expect(frame.toJson()['type'], frame.type);
      }
    });

    test('leaves out what a frame lacks', () {
      expect(frames[0].toJson().keys, {
        'type',
        'version',
        'os',
        'arch',
        'cores',
        'draining',
        'leases',
      });
      expect(frames[8].toJson().keys, {
        'type',
        'jobId',
        'leaseId',
        'ordinal',
        'state',
        'attempts',
      });
    });

    test('reads a type it does not know as UnknownRunnerFrame', () {
      final read = RunnerFrame.fromJson(const {'type': 'warp', 'speed': 9});

      expect(
        read,
        const UnknownRunnerFrame(
          type: 'warp',
          payload: {'type': 'warp', 'speed': 9},
        ),
      );
      expect(read.toJson(), {'type': 'warp', 'speed': 9});
    });

    test('refuses a frame without a type', () {
      expect(
        () => RunnerFrame.fromJson(const {'jobId': 'j'}),
        throwsFormatException,
      );
      expect(
        () => RunnerFrame.fromJson(const {'type': 3}),
        throwsFormatException,
      );
    });

    test('refuses fields that are missing or of the wrong type', () {
      final broken = <Map<String, dynamic>>[
        // A required field is missing.
        {'type': 'drain'},
        // A field of the wrong type.
        {'type': 'lease_accept', 'jobId': 1, 'leaseId': 'l'},
        // An optional field of the wrong type.
        {
          'type': 'hello',
          'version': 'v',
          'os': 'o',
          'arch': 'a',
          'cores': 1,
          'maxJobs': 'many',
          'leases': <Object?>[],
        },
        // A list of objects with an item that is not one.
        {
          'type': 'heartbeat',
          'leases': <Object?>['x'],
        },
        // A value that is not in the enum.
        {
          'type': 'step_state',
          'jobId': 'j',
          'leaseId': 'l',
          'ordinal': 0,
          'state': 'dancing',
          'attempts': 1,
        },
        // A time that is not a time.
        {
          'type': 'step_state',
          'jobId': 'j',
          'leaseId': 'l',
          'ordinal': 0,
          'state': 'running',
          'attempts': 1,
          'startedAt': 'yesterday',
        },
        // A job that is done in a state that is not an end.
        {
          'type': 'job_done',
          'jobId': 'j',
          'leaseId': 'l',
          'state': 'running',
          'lastChunk': 0,
        },
      ];

      for (final json in broken) {
        expect(
          () => RunnerFrame.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('EngineFrame', () {
    final frames = <EngineFrame>[
      const WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: '1.0.0',
        apiVersion: '1',
      ),
      const ProbeFrame(
        probeId: 'prb_1',
        commands: [
          ProbeCommand(id: 'git', executable: 'git', arguments: ['--version']),
          ProbeCommand(
            id: 'xcodebuild',
            executable: 'xcodebuild',
            arguments: ['-version'],
            timeoutSeconds: 10,
            requires: 'xcode_select',
            onlyOn: 'macos',
          ),
        ],
      ),
      LeaseOfferFrame(
        leaseId: 'lse_1',
        jobId: 'job_1',
        projectId: 'prj_1',
        sha: 'a' * 40,
        name: 'Build prod for android',
        stage: 1,
        capabilities: const ['android', 'flutter'],
        expiresAt: at,
        steps: const [
          LeaseStep(
            ordinal: 0,
            kind: 'build.android',
            sideEffect: false,
            state: StepState.pending,
            attempts: 0,
            input: {'artifact': 'aab'},
          ),
        ],
        secrets: const ['keystore'],
      ),
      LeaseOfferFrame(
        leaseId: 'lse_2',
        jobId: 'job_2',
        projectId: 'prj_1',
        stage: 0,
        capabilities: const [],
        expiresAt: at,
        steps: const [],
      ),
      const HeartbeatAckFrame(),
      HeartbeatAckFrame(
        leases: [LeaseGrant(jobId: 'job_1', leaseId: 'lse_1', until: at)],
      ),
      const ChunkAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        seq: 2,
        next: 1,
        status: ChunkStatus.gap,
      ),
      const DoneAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.failed,
      ),
      const CancelFrame(jobId: 'job_1', reason: 'Unknown lease.'),
      const CancelFrame(jobId: 'job_1', leaseId: 'lse_1', reason: 'Lapsed.'),
      const SecretValueFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        key: 'k',
        value: 'v',
      ),
      const SecretDeniedFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        key: 'k',
        reason: 'Not signing material.',
      ),
      const FaultFrame(code: 'invalid_frame', message: 'Bad.'),
    ];

    test('round-trips every frame through JSON', () {
      for (final frame in frames) {
        expect(EngineFrame.fromJson(wire(frame.toJson())), frame);
        expect(frame.toJson()['type'], frame.type);
      }
    });

    test('leaves out what a frame lacks', () {
      expect(frames[3].toJson().keys, {
        'type',
        'leaseId',
        'jobId',
        'projectId',
        'stage',
        'capabilities',
        'expiresAt',
        'steps',
        'secrets',
      });
      expect(frames[8].toJson().keys, {'type', 'jobId', 'reason'});
    });

    test('the welcome frame carries the 30 s and 90 s rules', () {
      final welcome = frames.first as WelcomeFrame;

      expect(welcome.heartbeatSeconds, runnerHeartbeatSeconds);
      expect(welcome.leaseSeconds, runnerLeaseSeconds);
      expect(runnerHeartbeatSeconds, 30);
      expect(runnerLeaseSeconds, 90);
    });

    test('reads a type it does not know as UnknownEngineFrame', () {
      final read = EngineFrame.fromJson(const {'type': 'warp'});

      expect(
        read,
        const UnknownEngineFrame(type: 'warp', payload: {'type': 'warp'}),
      );
      expect(read.toJson(), {'type': 'warp'});
    });

    test('refuses a frame that is not well formed', () {
      expect(
        () => EngineFrame.fromJson(const {'type': 'cancel'}),
        throwsFormatException,
      );
      // A list with an item that is not a string.
      expect(
        () => EngineFrame.fromJson(const {
          'type': 'lease_offer',
          'leaseId': 'l',
          'jobId': 'j',
          'projectId': 'p',
          'stage': 0,
          'capabilities': [1],
        }),
        throwsFormatException,
      );
    });
  });

  group('probe', () {
    test('a result succeeded when the command exited with 0', () {
      expect(
        const ProbeResult(
          id: 'a',
          status: ProbeStatus.exited,
          exitCode: 0,
        ).succeeded,
        isTrue,
      );
      expect(
        const ProbeResult(
          id: 'a',
          status: ProbeStatus.exited,
          exitCode: 1,
        ).succeeded,
        isFalse,
      );
      expect(
        const ProbeResult(id: 'a', status: ProbeStatus.timedOut).succeeded,
        isFalse,
      );
    });

    test('uses snake case for the statuses on the wire', () {
      expect(ProbeStatus.values.map((status) => status.wire), [
        'exited',
        'skipped',
        'not_started',
        'timed_out',
      ]);
      expect(ChunkStatus.values.map((status) => status.wire), [
        'stored',
        'duplicate',
        'gap',
      ]);
    });
  });

  test('the close codes are distinct and in the private range', () {
    final codes = {
      runnerReplacedCloseCode,
      runnerRevokedCloseCode,
      runnerTimeoutCloseCode,
      runnerProtocolCloseCode,
    };

    expect(codes, hasLength(4));
    expect(codes.every((code) => code >= 4000 && code < 5000), isTrue);
  });
}
