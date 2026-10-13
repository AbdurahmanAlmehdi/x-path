import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

String _describe(LogFrame frame) => switch (frame) {
  LogLineFrame(:final seq, :final step, :final text, :final stream) =>
    '$seq:$step:${stream.name}:$text',
  LogGapFrame(:final fromSeq, :final toSeq, :final count) =>
    'gap $fromSeq-$toSeq ($count)',
  LogEndFrame(:final state) => 'end ${state.wire}',
};

/// A store whose reads wait, and can hide the newest lines.
class _SlowStore extends InMemoryJobLogStore {
  int replayLimit = 1 << 30;

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) async* {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await for (final line in super.read(jobId, after: after)) {
      if (line.seq <= replayLimit) yield line;
    }
  }
}

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  /// A finished job that logged `one`, `two` (step 0) and `three` (step 1).
  Future<Job> finishedJob() async {
    engine.supervisor.handler = (process) async {
      if (process.spec.executable == 'first') {
        await process.emit('one');
        await process.emit('two', stream: LogStream.stderr);
      } else {
        await process.emit('three');
      }
      return 0;
    };
    final job = await engine.startJob(['first', 'second']);
    await engine.jobs.whenFinished(job.id);
    return job;
  }

  group('before the upgrade', () {
    test('answers 401 without a token', () async {
      final response = await engine.handshake('/jobs/job_1/logs', token: '');

      expect(response.statusCode, 401);
    });

    test('answers 426 for a plain request', () async {
      final job = await finishedJob();

      final response = await engine.request('/jobs/${job.id}/logs');

      expect(response.statusCode, 426);
      expect(errorCode(response), 'upgrade_required');
    });

    test('answers 400 for a cursor that is not a number', () async {
      final job = await finishedJob();

      for (final after in ['-1', 'x']) {
        final response = await engine.handshake(
          '/jobs/${job.id}/logs?after=$after',
        );

        expect(response.statusCode, 400, reason: after);
        expect(errorCode(response), 'invalid_request');
      }
    });

    test('answers 404 for an unknown job', () async {
      final response = await engine.handshake('/jobs/job_nope/logs');

      expect(response.statusCode, 404);
    });

    test('answers 409 for a cursor beyond the log', () async {
      final job = await finishedJob();

      final response = await engine.handshake('/jobs/${job.id}/logs?after=4');

      expect(response.statusCode, 409);
      expect(errorCode(response), 'resync_required');
    });
  });

  group('a job that ended', () {
    test('replays its whole log across steps, then ends', () async {
      final job = await finishedJob();

      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);
      final frames = await logs.all();

      expect(frames.map(_describe), [
        '1:0:stdout:one',
        '2:0:stderr:two',
        '3:1:stdout:three',
        'end succeeded',
      ]);
      expect((frames.first as LogLineFrame).at, DateTime.utc(2026, 10, 13, 9));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(logs.closeCode, 1000);
    });

    test('resumes after the last line the client saw', () async {
      final job = await finishedJob();

      final logs = await engine.connectLogs(job.id, after: 2);
      addTearDown(logs.close);

      expect((await logs.all()).map(_describe), [
        '3:1:stdout:three',
        'end succeeded',
      ]);
    });

    test('has nothing to replay after the newest line', () async {
      final job = await finishedJob();

      final logs = await engine.connectLogs(job.id, after: 3);
      addTearDown(logs.close);

      expect((await logs.all()).map(_describe), ['end succeeded']);
    });

    test('ends with the state the job is in', () async {
      engine.supervisor.handler = (process) async {
        await process.emit('boom');
        return 1;
      };
      final job = await engine.startJob(['x']);
      await engine.jobs.whenFinished(job.id);

      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);

      expect((await logs.all()).map(_describe), [
        '1:0:stdout:boom',
        'end failed',
      ]);
    });

    test('keeps numbering where a resumed job left off', () async {
      engine.supervisor.handler = (process) async {
        await process.emit('try');
        return 1;
      };
      final job = await engine.startJob(['x']);
      await engine.jobs.whenFinished(job.id);
      engine.supervisor.handler = (process) async {
        await process.emit('again');
        return 0;
      };
      await engine.jobs.resume(job.id);
      await engine.jobs.whenFinished(job.id);

      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);

      expect((await logs.all()).map(_describe), [
        '1:0:stdout:try',
        '2:0:stdout:again',
        'end succeeded',
      ]);
    });
  });

  group('a job that runs', () {
    test('sends what was logged, follows the job, then ends', () async {
      final proceed = Completer<void>();
      engine.supervisor.handler = (process) async {
        await process.emit('early');
        await proceed.future;
        await process.emit('late');
        return 0;
      };
      final job = await engine.startJob(['x']);
      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);

      expect(_describe(await logs.next()), '1:0:stdout:early');
      proceed.complete();

      expect((await logs.all()).map(_describe), [
        '2:0:stdout:late',
        'end succeeded',
      ]);
    });

    test('tells a client that the lines it missed are in the log', () async {
      await engine.close();
      final store = _SlowStore();
      engine = await TestEngine.start(logStore: store, logLiveCapacity: 2);
      final emitNow = Completer<void>();
      final proceed = Completer<void>();
      engine.supervisor.handler = (process) async {
        await emitNow.future;
        for (var i = 1; i <= 6; i++) {
          await process.emit('line $i');
        }
        await proceed.future;
        return 0;
      };
      final job = await engine.startJob(['x']);
      store.replayLimit = 2;
      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Six lines come while the engine is still reading the stored log.
      emitNow.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      proceed.complete();

      expect((await logs.all()).map(_describe), [
        '1:0:stdout:line 1',
        '2:0:stdout:line 2',
        'gap 3-4 (2)',
        '5:0:stdout:line 5',
        '6:0:stdout:line 6',
        'end succeeded',
      ]);
    });

    test('lets a client leave without harming the job', () async {
      final proceed = Completer<void>();
      engine.supervisor.handler = (process) async {
        await process.emit('one');
        await proceed.future;
        await process.emit('two');
        return 0;
      };
      final job = await engine.startJob(['x']);
      final logs = await engine.connectLogs(job.id);
      await logs.next();
      await logs.close();

      proceed.complete();
      final done = await engine.jobs.whenFinished(job.id);

      expect(done.state, JobState.succeeded);
      expect(engine.errors, isEmpty);
    });

    test('closes the socket when the engine shuts down', () async {
      engine.supervisor.handler = (process) async {
        await process.emit('one');
        await Completer<void>().future;
        return 0;
      };
      final job = await engine.startJob(['x']);
      final logs = await engine.connectLogs(job.id);
      addTearDown(logs.close);
      await logs.next();

      await engine.server.close();

      expect(await logs.all(), isEmpty);
      expect(logs.closeCode, 1000);
    });
  });
}
