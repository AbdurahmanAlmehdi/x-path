import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('SerialQueues', () {
    test('runs the actions of one key in order, one at a time', () async {
      final queues = SerialQueues();
      final log = <String>[];
      var running = 0;
      var most = 0;

      Future<void> action(String name, int ms) => queues.run('job', () async {
        most = running + 1 > most ? running + 1 : most;
        running++;
        log.add('start $name');
        await Future<void>.delayed(Duration(milliseconds: ms));
        log.add('end $name');
        running--;
      });

      await Future.wait([action('a', 5), action('b', 1), action('c', 0)]);

      expect(log, ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
      expect(most, 1);
      expect(queues.busyKeys, 0);
    });

    test('keys do not wait for each other', () async {
      final queues = SerialQueues();
      final slow = Completer<void>();
      final order = <String>[];

      final first = queues.run('a', () async {
        await slow.future;
        order.add('a');
      });
      await queues.run('b', () async => order.add('b'));
      expect(queues.busyKeys, 1);
      slow.complete();
      await first;

      expect(order, ['b', 'a']);
    });

    test('a failing action fails its own call only', () async {
      final queues = SerialQueues();

      final failing = queues.run<void>('a', () async => throw StateError('no'));
      final fine = queues.run('a', () async => 7);

      await expectLater(failing, throwsStateError);
      expect(await fine, 7);
      expect(queues.busyKeys, 0);
    });
  });
}
