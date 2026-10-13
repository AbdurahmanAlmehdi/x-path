import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// An [EventLog] in the `event` table that survives restarts.
///
/// Sequence numbers come from `AUTOINCREMENT`, so they never repeat, not even
/// after every row was pruned: a client whose cursor is from before an engine
/// restart resumes if its events are still inside the window. Events older
/// than [window] are pruned when the log opens and then at most once per
/// [pruneInterval] of [Clock] time, when an event is appended.
///
/// Only one process appends: the running engine.
class SqliteEventLog implements EventLog {
  /// Creates a log over a database and prunes it.
  new({
    required this._database,
    required this._clock,
    this.window = const Duration(days: 7),
    this.pruneInterval = const Duration(hours: 1),
  }) {
    prune();
  }

  /// How long an event stays available for resuming.
  final Duration window;

  /// The least time between two prunes triggered by [append].
  final Duration pruneInterval;

  final SqliteDatabase _database;
  final Clock _clock;
  final _subscribers = <StreamController<SequencedEvent>>{};
  late DateTime _lastPruned;

  @override
  int get head {
    final rows = _database.connection.select(
      "SELECT seq FROM sqlite_sequence WHERE name = 'event'",
    );
    return rows.isEmpty ? 0 : rows.single['seq'] as int;
  }

  @override
  bool canResume(int after) {
    final head = this.head;
    final oldest =
        _database.connection
                .select('SELECT min(seq) AS oldest FROM event')
                .single['oldest']
            as int?;
    return after >= (oldest == null ? head : oldest - 1) && after <= head;
  }

  @override
  SequencedEvent append(EngineEvent event) {
    final now = _clock.now();
    if (now.difference(_lastPruned) >= pruneInterval) prune();
    _database.connection.execute(
      'INSERT INTO event (type, payload, at) VALUES (?, ?, ?)',
      [event.type, jsonEncode(event.payload), toDatabaseTime(now)],
    );
    final logged = SequencedEvent(
      seq: _database.connection.lastInsertRowId,
      at: now,
      event: event,
    );
    _subscribers.toList().forEach((subscriber) => subscriber.add(logged));
    return logged;
  }

  /// Deletes the events older than [window] and returns how many it deleted.
  int prune() {
    final now = _clock.now();
    _lastPruned = now;
    _database.connection.execute('DELETE FROM event WHERE at < ?', [
      toDatabaseTime(now.subtract(window)),
    ]);
    return _database.connection.updatedRows;
  }

  @override
  Stream<SequencedEvent> subscribe({int? after}) {
    late final StreamController<SequencedEvent> controller;
    controller = StreamController<SequencedEvent>(
      onListen: () {
        if (after != null && !canResume(after)) {
          controller.addError(EventGapException(after, head));
          unawaited(controller.close());
          return;
        }
        if (after != null) _eventsAfter(after).forEach(controller.add);
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

  Iterable<SequencedEvent> _eventsAfter(int after) => _database.connection
      .select(
        'SELECT seq, type, payload, at FROM event WHERE seq > ? ORDER BY seq',
        [after],
      )
      .map(_fromRow);

  static SequencedEvent _fromRow(Row row) => SequencedEvent(
    seq: row['seq'] as int,
    at: fromDatabaseTime(row['at'] as int),
    event: EngineEvent.fromJson(
      row['type'] as String,
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    ),
  );
}
