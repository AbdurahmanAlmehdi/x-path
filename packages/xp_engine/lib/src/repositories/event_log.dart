import 'dart:async';
import 'dart:collection';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';

/// The cursor of a resuming client is outside what the log still holds.
class EventGapException implements Exception {
  /// Creates the exception for a client that asked to resume [after].
  const new(this.after, this.head);

  /// The cursor the client asked to resume after.
  final int after;

  /// The sequence number of the newest logged event.
  final int head;

  @override
  String toString() =>
      'EventGapException: cannot resume after $after (log head is $head)';
}

/// Append-only log of engine events with sequence numbers, so that a client
/// can reconnect and receive what it missed.
///
/// The window of retained events is bounded. [InMemoryEventLog] forgets
/// everything on exit; `xp_adapters` has a SQLite log that survives restarts.
abstract interface class EventLog {
  /// The sequence number of the newest event, or 0 when none was logged.
  int get head;

  /// Whether a client that has seen everything up to [after] can resume.
  bool canResume(int after);

  /// Logs [event], giving it the next sequence number and the current time.
  SequencedEvent append(EngineEvent event);

  /// Events as they are logged.
  ///
  /// With [after], first the retained events with a greater sequence number,
  /// in order. If [after] cannot be resumed the stream fails with an
  /// [EventGapException]. The stream starts when it is listened to.
  Stream<SequencedEvent> subscribe({int? after});

  /// Ends every open subscription.
  Future<void> close();
}

/// An [EventLog] in memory that keeps the newest [capacity] events.
class InMemoryEventLog implements EventLog {
  /// Creates an empty log.
  new({required this._clock, this.capacity = 1000})
    : assert(capacity > 0, 'capacity must be positive');

  /// How many events are kept for resuming.
  final int capacity;

  final Clock _clock;
  final _events = Queue<SequencedEvent>();
  final _subscribers = <StreamController<SequencedEvent>>{};
  var _head = 0;

  @override
  int get head => _head;

  @override
  bool canResume(int after) {
    final oldest = _events.isEmpty ? _head : _events.first.seq - 1;
    return after >= oldest && after <= _head;
  }

  @override
  SequencedEvent append(EngineEvent event) {
    final logged = SequencedEvent(seq: ++_head, at: _clock.now(), event: event);
    _events.add(logged);
    if (_events.length > capacity) _events.removeFirst();
    _subscribers.toList().forEach((subscriber) => subscriber.add(logged));
    return logged;
  }

  @override
  Stream<SequencedEvent> subscribe({int? after}) {
    late final StreamController<SequencedEvent> controller;
    controller = StreamController<SequencedEvent>(
      onListen: () {
        if (after != null && !canResume(after)) {
          controller.addError(EventGapException(after, _head));
          unawaited(controller.close());
          return;
        }
        if (after != null) {
          _events.where((e) => e.seq > after).forEach(controller.add);
        }
        _subscribers.add(controller);
      },
      onCancel: () => _subscribers.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<void> close() async {
    final open = _subscribers.toList();
    _subscribers.clear();
    await Future.wait<void>(open.map((subscriber) => subscriber.close()));
  }
}
