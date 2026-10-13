import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

EngineEvent _event(int n) => EngineStarted(version: '$n', apiVersion: '1');

List<int> _seqs(Iterable<SequencedEvent> events) =>
    events.map((e) => e.seq).toList();

void main() {
  late ManualClock clock;
  late InMemoryEventLog log;

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 10, 13));
    log = InMemoryEventLog(clock: clock, capacity: 3);
  });

  group('append', () {
    test('numbers events from 1 and stamps them with the clock', () {
      final first = log.append(_event(1));
      clock.advance(const Duration(seconds: 5));
      final second = log.append(_event(2));

      expect(first.seq, 1);
      expect(first.at, DateTime.utc(2026, 10, 13));
      expect(second.seq, 2);
      expect(second.at, DateTime.utc(2026, 10, 13, 0, 0, 5));
      expect(log.head, 2);
    });

    test('starts with head 0', () {
      expect(log.head, 0);
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
      }

      // Events 3, 4 and 5 are kept.
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
        }

        await expectLater(
          log.subscribe(after: 0),
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

    test('checks the cursor when listening, not when subscribing', () async {
      final stream = log.subscribe(after: 0);
      for (var i = 1; i <= 5; i++) {
        log.append(_event(i));
      }

      await expectLater(stream, emitsError(isA<EventGapException>()));
    });

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

  test('EventGapException says what was asked and what is there', () {
    expect(
      const EventGapException(2, 9).toString(),
      'EventGapException: cannot resume after 2 (log head is 9)',
    );
  });
}
