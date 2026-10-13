// Every subscription here ends with the fan-out it listens to.
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

String _describe(FanOutEvent<int> event) => switch (event) {
  FanOutItem(:final value) => '$value',
  FanOutGap(:final fromSeq, :final toSeq, :final count) =>
    'gap $fromSeq-$toSeq ($count)',
};

/// Lets the microtasks that deliver queued values run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FanOut<int> fanOut;

  setUp(() => fanOut = FanOut(seqOf: (value) => value));

  group('subscribe', () {
    test('hands every value to every subscriber, in order', () async {
      final first = <int>[];
      final second = <int>[];
      fanOut.subscribe().listen(first.add);
      fanOut.subscribe().listen(second.add);

      for (var i = 1; i <= 3; i++) {
        await fanOut.add(i);
      }

      expect(first, [1, 2, 3]);
      expect(second, [1, 2, 3]);
    });

    test('starts at the next value after it was created', () async {
      await fanOut.add(1);
      final received = <int>[];
      fanOut.subscribe().listen(received.add);

      await fanOut.add(2);

      expect(received, [2]);
    });

    test('queues values until it is listened to', () async {
      final stream = fanOut.subscribe();
      await fanOut.add(1);
      await fanOut.add(2);

      final received = <int>[];
      stream.listen(received.add);
      await settle();

      expect(received, [1, 2]);
    });

    test('makes add wait while the reader is behind', () async {
      final received = <int>[];
      final subscription = fanOut.subscribe(capacity: 2).listen(received.add)
        ..pause();
      await fanOut.add(1);
      var added = false;
      final second = fanOut.add(2).then((_) => added = true);
      await Future<void>.delayed(Duration.zero);

      expect(added, isFalse, reason: 'the queue holds 2 values');

      subscription.resume();
      await second;
      await settle();

      expect(received, [1, 2]);
      expect(added, isTrue);
    });

    test('never drops a value, however slow the reader', () async {
      final received = <int>[];
      final subscription = fanOut.subscribe(capacity: 1).listen(received.add);
      for (var i = 1; i <= 5; i++) {
        subscription.pause();
        final added = fanOut.add(i);
        await Future<void>.delayed(Duration.zero);
        subscription.resume();
        await added;
        await settle();
      }

      expect(received, [1, 2, 3, 4, 5]);
    });

    test('stops queueing for a subscriber that cancelled', () async {
      final received = <int>[];
      final subscription = fanOut.subscribe(capacity: 1).listen(received.add);
      await fanOut.add(1);
      await subscription.cancel();

      await fanOut.add(2);
      await fanOut.add(3);

      expect(received, [1]);
    });

    test('lets the reader pause from inside its handler', () async {
      final received = <int>[];
      late StreamSubscription<int> subscription;
      subscription = fanOut.subscribe().listen((value) {
        received.add(value);
        subscription.pause(
          Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      });

      await fanOut.add(1);
      await fanOut.add(2);

      expect(received, [1]);
      await fanOut.close();
      expect(received, [1, 2]);
    });
  });

  group('watch', () {
    test('hands values to a reader that keeps up', () async {
      final received = <String>[];
      fanOut.watch().listen((event) => received.add(_describe(event)));

      await fanOut.add(1);
      await fanOut.add(2);

      expect(received, ['1', '2']);
    });

    test('drops the oldest values of a reader that falls behind', () async {
      final received = <String>[];
      final subscription =
          fanOut
              .watch(capacity: 2)
              .listen((event) => received.add(_describe(event)))
            ..pause();
      for (var i = 1; i <= 5; i++) {
        await fanOut.add(i);
      }
      subscription.resume();
      await settle();

      expect(received, ['gap 1-3 (3)', '4', '5']);
    });

    test('reports a gap before the values that follow it', () async {
      final received = <String>[];
      final subscription = fanOut
          .watch(capacity: 1)
          .listen((event) => received.add(_describe(event)));
      await fanOut.add(1);
      subscription.pause();
      await fanOut.add(2);
      await fanOut.add(3);
      subscription.resume();
      await settle();
      await fanOut.add(4);
      subscription.pause();
      await fanOut.add(5);
      await fanOut.add(6);
      subscription.resume();
      await settle();

      expect(received, ['1', 'gap 2-2 (1)', '3', '4', 'gap 5-5 (1)', '6']);
    });

    test('never makes add wait', () async {
      fanOut.watch(capacity: 1).listen((_) {}).pause();

      await fanOut.add(1);
      await fanOut.add(2);
      await fanOut.add(3);
    });

    test('is independent of the lossless subscribers', () async {
      final all = <int>[];
      fanOut.subscribe().listen(all.add);
      final live = <String>[];
      final watcher =
          fanOut
              .watch(capacity: 1)
              .listen((event) => live.add(_describe(event)))
            ..pause();
      for (var i = 1; i <= 3; i++) {
        await fanOut.add(i);
      }
      watcher.resume();
      await settle();

      expect(all, [1, 2, 3]);
      expect(live, ['gap 1-2 (2)', '3']);
    });
  });

  group('close', () {
    test('ends the streams after what they have queued', () async {
      final received = <int>[];
      var done = false;
      final subscription = fanOut.subscribe().listen(
        received.add,
        onDone: () => done = true,
      )..pause();
      await fanOut.add(1);
      await fanOut.add(2);

      final closing = fanOut.close();
      await Future<void>.delayed(Duration.zero);

      expect(done, isFalse);
      expect(fanOut.isClosed, isTrue);

      subscription.resume();
      await closing;
      await settle();

      expect(received, [1, 2]);
      expect(done, isTrue);
    });

    test('ends a watcher after the gap and the values it has queued', () async {
      final received = <String>[];
      var done = false;
      final subscription =
          fanOut
              .watch(capacity: 1)
              .listen(
                (event) => received.add(_describe(event)),
                onDone: () => done = true,
              )
            ..pause();
      await fanOut.add(1);
      await fanOut.add(2);

      final closing = fanOut.close();
      subscription.resume();
      await closing;
      await settle();

      expect(received, ['gap 1-1 (1)', '2']);
      expect(done, isTrue);
    });

    test('ends streams that nothing is queued for at once', () async {
      var done = false;
      fanOut.subscribe().listen((_) {}, onDone: () => done = true);

      await fanOut.close();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });

    test('does not wait for a watcher that is paused', () async {
      fanOut.watch().listen((_) {}).pause();
      await fanOut.add(1);

      await fanOut.close();
    });

    test('does not wait for a reader that cancelled', () async {
      final subscription = fanOut.subscribe().listen((_) {})..pause();
      await fanOut.add(1);
      await subscription.cancel();

      await fanOut.close();
    });

    test('ignores values added afterwards, and a second close', () async {
      final received = <int>[];
      fanOut.subscribe().listen(received.add);
      await fanOut.close();

      await fanOut.add(1);
      await fanOut.close();

      expect(received, isEmpty);
    });
  });
}
