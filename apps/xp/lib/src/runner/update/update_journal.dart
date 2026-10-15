import 'dart:convert';
import 'dart:io';

/// How many times a new version may start without reaching the engine before
/// the runner goes back to the version before.
const maxUnconfirmedStarts = 3;

/// An update that has not proven itself: [to] was switched to, [from] was
/// running, and the runner has started [starts] times since without being
/// welcomed by the engine.
class PendingUpdate {
  /// Creates the record.
  const new({required this.from, required this.to, this.starts = 0});

  /// Reads the record from its JSON form.
  factory fromJson(Map<String, dynamic> json) => PendingUpdate(
    from: json['from'] as String,
    to: json['to'] as String,
    starts: json['starts'] as int,
  );

  /// The version the runner was on.
  final String from;

  /// The version it switched to.
  final String to;

  /// How many times [to] started without being welcomed.
  final int starts;

  /// The JSON form.
  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'starts': starts};
}

/// What a start of the runner has to do about an unproven update.
sealed class StartDecision {
  const new();
}

/// Run as usual.
final class ProceedStart extends StartDecision {
  /// Creates the decision.
  const new();
}

/// The new version failed to start often enough: go back to [version].
final class RollBack extends StartDecision {
  /// Creates the decision.
  const new(this.version, this.failed);

  /// The version to go back to.
  final String version;

  /// The version that failed.
  final String failed;
}

/// The record of the update in progress, in `update.json` of the data
/// directory (D-24): the version the runner switched to, how often it started
/// since, and the version it went back from.
///
/// - [begin] writes it before the switch.
/// - [noteStart] counts a start of the new version and, after
///   `maxUnconfirmedStarts`, tells the runner to go back.
/// - [confirm] clears it when the engine welcomed the new version.
/// - [rolledBack] remembers a version that failed, so that the runner does
///   not update to it again (it would loop); a newer engine version is
///   another version.
class UpdateJournal {
  /// Creates the journal in the file [path].
  const new(this.path);

  /// The file.
  final String path;

  /// The update in progress, or `null`.
  PendingUpdate? get pending => _read().$1;

  /// The version the runner went back from, or `null`.
  String? get blocked => _read().$2;

  /// Records that the runner is switching from [from] to [to].
  void begin({required String from, required String to}) =>
      _write(PendingUpdate(from: from, to: to), blocked);

  /// Forgets the update in progress (the switch failed).
  void abandon() => _write(null, blocked);

  /// Called at every start of the runner, which is running [running].
  ///
  /// An update to [running] that has not been confirmed counts one more start;
  /// the one after [maxUnconfirmedStarts] is told to go back. A record of
  /// another version (the runner was rolled back or switched by hand) is
  /// dropped.
  StartDecision noteStart(String running) {
    final (pending, blocked) = _read();
    if (pending == null) return const ProceedStart();
    if (pending.to != running) {
      _write(null, blocked);
      return const ProceedStart();
    }
    final starts = pending.starts + 1;
    if (starts > maxUnconfirmedStarts) {
      return RollBack(pending.from, pending.to);
    }
    _write(
      PendingUpdate(from: pending.from, to: pending.to, starts: starts),
      blocked,
    );
    return const ProceedStart();
  }

  /// The engine welcomed the runner that runs [running]: the update, if
  /// that was it, has proven itself. Returns the version before it, to keep
  /// for a rollback by hand, or `null` when no update was waiting.
  String? confirm(String running) {
    final (pending, blocked) = _read();
    if (pending == null || pending.to != running) return null;
    _write(null, blocked);
    return pending.from;
  }

  /// The runner went back from [failed]: do not update to it again.
  void rolledBack(String failed) => _write(null, failed);

  (PendingUpdate?, String?) _read() {
    final file = File(path);
    if (!file.existsSync()) return (null, null);
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final pending = json['pending'];
      return (
        pending == null
            ? null
            : PendingUpdate.fromJson(pending as Map<String, dynamic>),
        json['blocked'] as String?,
      );
    } on Object {
      // A record that cannot be read is no record: an update that cannot be
      // watched is not rolled back, but it is not a reason to fail either.
      return (null, null);
    }
  }

  void _write(PendingUpdate? pending, String? blocked) {
    final file = File(path);
    if (pending == null && blocked == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.parent.createSync(recursive: true);
    File('$path.partial')
      ..writeAsStringSync(
        jsonEncode({'pending': ?pending?.toJson(), 'blocked': ?blocked}),
      )
      ..renameSync(path);
  }
}
