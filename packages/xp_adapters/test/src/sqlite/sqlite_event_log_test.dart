import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

EngineEvent _event(int n) => EngineStarted(version: '$n', apiVersion: '1');

List<int> _seqs(Iterable<SequencedEvent> events) =>
    events.map((e) => e.seq).toList();

void main() {
  late ManualClock clock;
  late SqliteDatabase database;
  late SqliteEventLog log;

  SqliteEventLog openLog({
    Duration window = const Duration(days: 7),
    Duration pruneInterval = const Duration(hours: 1),
  }) => SqliteEventLog(
    database: database,
    clock: clock,
    window: window,
    pruneInterval: pruneInterval,
  );

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 10, 13));
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    log = openLog();
  });

  group('append', () {
    test('numbers events from 1 and stamps them with the clock', () {
      final first = log.append(_event(1));
      clock.advance(const Duration(seconds: 5));
      final second = log.append(_event(2));

      expect(first.seq, 1);
      expect(first.at, DateTime.utc(2026, 10, 13));
      expect(first.event, _event(1));
      expect(second.seq, 2);
      expect(second.at, DateTime.utc(2026, 10, 13, 0, 0, 5));
      expect(log.head, 2);
    });

    test('starts with head 0', () {
      expect(log.head, 0);
    });

    test('stores the event type, payload and time', () {
      clock.advance(const Duration(microseconds: 1234567));
      log.append(_event(7));

      final row = database.connection.select('SELECT * FROM event').single;
      expect(row['type'], 'engine.started');
      expect(row['payload'], '{"version":"7","apiVersion":"1"}');
      expect(
        row['at'],
        DateTime.utc(2026, 10, 13, 0, 0, 1, 234, 567).microsecondsSinceEpoch,
      );
    });
  });

  group('canResume', () {
    test('accepts only 0 on an empty log', () {
      expect(log.canResume(0), isTrue);
      expect(log.canResume(1), isFalse);
      expect(log.canResume(-1), isFalse);
    });

    test('accepts cursors from just before the oldest event to the head', () {
      for (var i = 1; i <= 5; i++) {
        log.append(_event(i));
        clock.advance(const Duration(days: 1));
      }
      // Events 1 and 2 are older than the 3-day window.
      openLog(window: const Duration(days: 3));

      expect(log.canResume(1), isFalse);
      expect(log.canResume(2), isTrue);
      expect(log.canResume(5), isTrue);
      expect(log.canResume(6), isFalse);
    });
  });

  group('subscribe', () {
    test('without a cursor delivers only live events', () async {
      log.append(_event(1));
      final received = <SequencedEvent>[];
      final subscription = log.subscribe().listen(received.add);

      log.append(_event(2));
      await pumpEventQueue();

      expect(_seqs(received), [2]);
      await subscription.cancel();
    });

    test('with a cursor replays the missed events, then goes live', () async {
      for (var i = 1; i <= 3; i++) {
        log.append(_event(i));
      }
      final received = <SequencedEvent>[];
      final subscription = log.subscribe(after: 1).listen(received.add);

      log.append(_event(4));
      await pumpEventQueue();

      expect(_seqs(received), [2, 3, 4]);
      expect(received.first.event, _event(2));
      await subscription.cancel();
    });

    test('with the head as cursor replays nothing', () async {
      log.append(_event(1));
      final received = <SequencedEvent>[];
      final subscription = log.subscribe(after: 1).listen(received.add);
      await pumpEventQueue();

      expect(received, isEmpty);
      await subscription.cancel();
    });

    test(
      'fails with an EventGapException when the cursor is too old',
      () async {
        for (var i = 1; i <= 5; i++) {
          log.append(_event(i));
          clock.advance(const Duration(days: 1));
        }
        log.prune();
        final trimmed = openLog(window: const Duration(days: 3));

        await expectLater(
          trimmed.subscribe(after: 0),
          emitsInOrder([
            emitsError(
              isA<EventGapException>()
                  .having((e) => e.after, 'after', 0)
                  .having((e) => e.head, 'head', 5),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test('stops delivering after the listener cancels', () async {
      final received = <SequencedEvent>[];
      final subscription = log.subscribe().listen(received.add);
      await subscription.cancel();

      log.append(_event(1));
      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });

  test('close ends every open subscription', () async {
    final done = Completer<void>();
    log.subscribe().listen((_) {}, onDone: done.complete);
    await pumpEventQueue();

    await log.close();

    await done.future;
  });

  group('window', () {
    test('keeps seven days by default', () {
      expect(log.window, const Duration(days: 7));
      expect(log.pruneInterval, const Duration(hours: 1));
    });

    test('prune deletes events older than the window and counts them', () {
      log.append(_event(1));
      clock.advance(const Duration(days: 6));
      log.append(_event(2));
      clock.advance(const Duration(days: 2));

      expect(log.prune(), 1);

      expect(
        database.connection
            .select('SELECT seq FROM event')
            .map((r) => r['seq']),
        [2],
      );
      expect(log.prune(), 0);
    });

    test('an event exactly as old as the window is kept', () {
      log.append(_event(1));
      clock.advance(const Duration(days: 7));

      expect(log.prune(), 0);
    });

    test('opening the log prunes', () {
      log.append(_event(1));
      clock.advance(const Duration(days: 8));

      openLog();

      expect(database.connection.select('SELECT seq FROM event'), isEmpty);
    });

    test('append prunes once per interval', () {
      log.append(_event(1));
      clock.advance(const Duration(days: 8));
      log.append(_event(2)); // more than an hour since opening: prunes 1
      clock.advance(const Duration(minutes: 1));

      expect(_remaining(database), [2]);

      clock.advance(const Duration(days: 8));
      log.append(_event(3));

      expect(_remaining(database), [3]);
    });

    test('append does not prune again within the interval', () {
      log = openLog(window: const Duration(minutes: 10))..append(_event(1));
      clock.advance(const Duration(minutes: 30));
      log.append(_event(2)); // 30 min < 1 h since opening: no prune

      expect(_remaining(database), [1, 2]);
    });

    test('sequence numbers never repeat, even after everything is pruned', () {
      log
        ..append(_event(1))
        ..append(_event(2));
      clock.advance(const Duration(days: 30));
      log.prune();

      expect(_remaining(database), isEmpty);
      expect(log.head, 2);
      expect(log.canResume(2), isTrue);
      expect(log.canResume(1), isFalse);
      expect(log.append(_event(3)).seq, 3);
    });
  });

  group('restart', () {
    test('a new log over the same database continues the numbering', () {
      log
        ..append(_event(1))
        ..append(_event(2));

      final restarted = openLog();

      expect(restarted.head, 2);
      expect(restarted.append(_event(3)).seq, 3);
    });

    test('a client cursor from before the restart still resumes', () async {
      log
        ..append(_event(1))
        ..append(_event(2));
      clock.advance(const Duration(hours: 2));
      final restarted = openLog()..append(_event(3));

      expect(restarted.canResume(1), isTrue);
      final received = await restarted.subscribe(after: 1).take(2).toList();

      expect(_seqs(received), [2, 3]);
      expect(received.last.at, DateTime.utc(2026, 10, 13, 2));
    });

    test('a cursor from before the window cannot resume', () {
      log.append(_event(1));
      clock.advance(const Duration(days: 8));
      final restarted = openLog()..append(_event(2));

      expect(restarted.canResume(0), isFalse);
      expect(restarted.canResume(1), isTrue);
    });

    test('survives closing and reopening a database file', () {
      final path = '${tempDirectory().path}/xpath.db';
      var file = SqliteDatabase.open(path);
      SqliteEventLog(database: file, clock: clock)
        ..append(_event(1))
        ..append(_event(2));
      file.close();

      file = SqliteDatabase.open(path);
      addTearDown(file.close);
      final reopened = SqliteEventLog(database: file, clock: clock);

      expect(reopened.head, 2);
      expect(reopened.canResume(0), isTrue);
    });

    test('keeps the payload of an event this version does not know', () async {
      database.connection.execute(
        'INSERT INTO event (type, payload, at) VALUES (?, ?, ?)',
        [
          'job.exploded',
          '{"why":"unknown"}',
          clock.now().microsecondsSinceEpoch,
        ],
      );

      final received = await log.subscribe(after: 0).take(1).toList();

      expect(
        received.single.event,
        const UnknownEvent(type: 'job.exploded', payload: {'why': 'unknown'}),
      );
    });
  });
}

List<Object?> _remaining(SqliteDatabase database) => database.connection
    .select('SELECT seq FROM event ORDER BY seq')
    .map((row) => row['seq'])
    .toList();
