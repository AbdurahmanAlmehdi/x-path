import 'package:test/test.dart';
import 'package:xp/src/runner/job/chunk_log_store.dart';
import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

ChunkLine _line(String text, {int step = 0}) => ChunkLine(
  step: step,
  at: DateTime.utc(2026, 10, 14, 12),
  stream: LogStream.stdout,
  text: text,
);

void main() {
  late List<RunnerFrame> sent;
  late LeaseOutbox outbox;

  setUp(() {
    sent = [];
    outbox = LeaseOutbox(
      jobId: 'job_1',
      leaseId: 'lse_1',
      send: sent.add,
      maxLines: 3,
      flushDelay: const Duration(milliseconds: 20),
    );
  });

  List<LogChunkFrame> chunks() => sent.whereType<LogChunkFrame>().toList();

  group('log chunks', () {
    test('are numbered from 1 and cut at the most lines', () {
      for (final text in ['a', 'b', 'c', 'd']) {
        outbox.line(_line(text));
      }

      expect(chunks().single.seq, 1);
      expect([for (final l in chunks().single.lines) l.text], ['a', 'b', 'c']);
      expect(chunks().single.jobId, 'job_1');
      expect(chunks().single.leaseId, 'lse_1');
      expect(outbox.lastChunk, 1);
    });

    test('are sent by themselves after a short while', () async {
      outbox.line(_line('a'));
      expect(chunks(), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(chunks().single.lines.single.text, 'a');
    });

    test('are sent when asked, once', () {
      outbox
        ..line(_line('a'))
        ..flush()
        ..flush();

      expect(chunks(), hasLength(1));
    });

    test('are dropped from memory when the engine has them', () {
      outbox
        ..line(_line('a'))
        ..flush()
        ..line(_line('b'))
        ..flush();
      sent.clear();

      outbox
        ..chunkAcknowledged(
          const ChunkAckFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            seq: 1,
            next: 2,
            status: ChunkStatus.stored,
          ),
        )
        ..resend();

      expect(chunks().map((c) => c.seq), [2]);
    });

    test('a duplicate is acknowledged like a stored chunk', () {
      outbox
        ..line(_line('a'))
        ..flush()
        ..chunkAcknowledged(
          const ChunkAckFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            seq: 1,
            next: 2,
            status: ChunkStatus.duplicate,
          ),
        );
      sent.clear();

      outbox.resend();

      expect(chunks(), isEmpty);
    });

    test('are sent again from where the engine wants them after a gap', () {
      for (final text in ['a', 'b', 'c']) {
        outbox
          ..line(_line(text))
          ..flush();
      }
      sent.clear();

      outbox.chunkAcknowledged(
        const ChunkAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          seq: 3,
          next: 2,
          status: ChunkStatus.gap,
        ),
      );

      expect(chunks().map((c) => c.seq), [2, 3]);
    });
  });

  group('the end of the job', () {
    test('sends the lines that wait, then job_done with the last chunk', () {
      outbox
        ..line(_line('a'))
        ..finish(state: JobState.failed, message: 'Step 1 failed.');

      expect(sent.map((f) => f.type), ['log_chunk', 'job_done']);
      final done = sent.last as JobDoneFrame;
      expect(done.state, JobState.failed);
      expect(done.message, 'Step 1 failed.');
      expect(done.lastChunk, 1);
      expect(outbox.awaitsAcknowledgement, isTrue);
    });

    test('is sent again, after the missing chunks, when the log has a gap', () {
      outbox
        ..line(_line('a'))
        ..finish(state: JobState.succeeded);
      sent.clear();

      outbox.chunkAcknowledged(
        const ChunkAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          seq: 1,
          next: 1,
          status: ChunkStatus.gap,
        ),
      );

      expect(sent.map((f) => f.type), ['log_chunk', 'job_done']);
    });

    test('is acknowledged once, and nothing is kept after that', () async {
      outbox
        ..line(_line('a'))
        ..step(
          const StepStateFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            ordinal: 0,
            state: StepState.succeeded,
            attempts: 1,
          ),
        )
        ..finish(state: JobState.succeeded)
        ..doneAcknowledged()
        ..doneAcknowledged();
      sent.clear();

      outbox.resend();

      expect(sent, isEmpty);
      expect(outbox.isAcknowledged, isTrue);
      expect(outbox.awaitsAcknowledgement, isFalse);
      await outbox.acknowledged;
    });

    test('is sent with everything else after a reconnect', () {
      outbox
        ..step(
          const StepStateFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            ordinal: 1,
            state: StepState.running,
            attempts: 1,
          ),
        )
        ..step(
          const StepStateFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            ordinal: 0,
            state: StepState.succeeded,
            attempts: 1,
          ),
        )
        ..line(_line('a'))
        ..finish(state: JobState.succeeded);
      sent.clear();

      outbox.resend();

      expect(sent.map((f) => f.type), [
        'log_chunk',
        'step_state',
        'step_state',
        'job_done',
      ]);
      expect(
        [for (final f in sent.whereType<StepStateFrame>()) f.ordinal],
        [0, 1],
      );
    });
  });

  test('a step state is kept in its newest form', () {
    outbox
      ..step(
        const StepStateFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          ordinal: 0,
          state: StepState.running,
          attempts: 1,
        ),
      )
      ..step(
        const StepStateFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          ordinal: 0,
          state: StepState.failed,
          attempts: 1,
          message: 'Boom.',
        ),
      );
    sent.clear();

    outbox.resend();

    expect((sent.single as StepStateFrame).state, StepState.failed);
  });

  test('abandon drops what waits and what is kept', () async {
    outbox
      ..line(_line('a'))
      ..flush()
      ..line(_line('b'))
      ..abandon();
    sent.clear();

    outbox.resend();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(sent, isEmpty);
    expect(outbox.awaitsAcknowledgement, isFalse);
  });

  group('the log store', () {
    test('turns the lines of a step into lines of a chunk', () async {
      final store = ChunkLogStore(outbox);
      final logs = JobLogs(store: store);
      await logs.begin('job_1');
      final step = await logs.openStep('job_1', 1, 'command');

      await step.record(
        OutputLine(
          seq: 1,
          timestamp: DateTime.utc(2026, 10, 14, 12),
          stream: LogStream.stderr,
          text: 'warning',
        ),
      );
      outbox.flush();
      await step.close();

      expect(step.path, 'lease/job_1/1-command');
      final line = chunks().single.lines.single;
      expect(line.step, 1);
      expect(line.stream, LogStream.stderr);
      expect(line.text, 'warning');
      expect(await store.head('job_1'), 0);
      expect(await store.read('job_1').toList(), isEmpty);
    });
  });
}
