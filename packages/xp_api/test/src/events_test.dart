import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9, 30);

  group('SequencedEvent', () {
    test('serializes seq, time, type and payload', () {
      final event = SequencedEvent(
        seq: 3,
        at: at,
        event: const EngineStarted(version: '0.0.1', apiVersion: '1'),
      );

      expect(event.toJson(), {
        'seq': 3,
        'at': '2026-10-13T09:30:00.000Z',
        'type': 'engine.started',
        'payload': {'version': '0.0.1', 'apiVersion': '1'},
      });
    });

    test('writes local times as UTC', () {
      final local = DateTime.utc(2026, 10, 13, 9, 30).toLocal();
      final event = SequencedEvent(
        seq: 1,
        at: local,
        event: const StreamOpened(),
      );

      expect(event.toJson()['at'], '2026-10-13T09:30:00.000Z');
    });

    test('round-trips every known event', () {
      for (final event in <EngineEvent>[
        const EngineStarted(version: '0.0.1', apiVersion: '1'),
        const StreamOpened(),
        const ProjectAdded(projectId: 'prj_1', fullName: 'o/r'),
        const ProjectScanned(projectId: 'prj_1', errors: 1, warnings: 2),
        const ProjectRemoved(projectId: 'prj_1'),
      ]) {
        final sequenced = SequencedEvent(seq: 9, at: at, event: event);

        expect(SequencedEvent.fromJson(sequenced.toJson()), sequenced);
      }
    });

    test('reads an event of an unknown type as UnknownEvent', () {
      final read = SequencedEvent.fromJson(const {
        'seq': 4,
        'at': '2026-10-13T09:30:00.000Z',
        'type': 'job.updated',
        'payload': {'id': 'j1'},
      });

      expect(
        read.event,
        const UnknownEvent(type: 'job.updated', payload: {'id': 'j1'}),
      );
      expect(read.toJson()['type'], 'job.updated');
      expect(read.toJson()['payload'], {'id': 'j1'});
    });
  });

  group('EngineEvent', () {
    test('exhaustive switch covers every subtype', () {
      String describe(EngineEvent event) => switch (event) {
        EngineStarted() => 'started',
        StreamOpened() => 'opened',
        ProjectAdded() => 'added',
        ProjectScanned() => 'scanned',
        ProjectRemoved() => 'removed',
        UnknownEvent() => 'unknown',
      };

      expect(describe(const StreamOpened()), 'opened');
      expect(
        describe(const ProjectAdded(projectId: 'p', fullName: 'o/r')),
        'added',
      );
      expect(
        describe(const ProjectScanned(projectId: 'p', errors: 0, warnings: 0)),
        'scanned',
      );
      expect(describe(const ProjectRemoved(projectId: 'p')), 'removed');
      expect(
        describe(EngineEvent.fromJson('x', const <String, dynamic>{})),
        'unknown',
      );
      expect(
        describe(
          EngineEvent.fromJson('engine.started', const {
            'version': 'v',
            'apiVersion': '1',
          }),
        ),
        'started',
      );
    });

    test('stream.opened has an empty payload and compares by value', () {
      expect(const StreamOpened().payload, isEmpty);
      expect(const StreamOpened().props, isEmpty);
    });
  });
}
