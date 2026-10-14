import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The process groups of the steps that run, kept on disk, so that a runner
/// that was killed can stop what it left behind when it starts again
/// (ADR 0003, D-18). The engine does the same for its own jobs with the
/// `pgid` of the step records.
///
/// A step records its group when it starts a process and forgets it when the
/// process ends, so only the steps that were running when the runner died
/// have one. A group id can in theory belong to an unrelated group by the
/// time of the next start, if the machine rebooted; [ProcessGroupKiller] only
/// signals groups that are alive and never one below 2.
class PgidJournal {
  /// Creates the journal in [directory].
  new(String directory) : _file = File(p.join(directory, 'pgids.json'));

  final File _file;
  final _groups = <String, int>{};
  Future<void> _tail = Future<void>.value();

  /// Records the group [pgid] of step [ordinal] of [jobId], or forgets it when
  /// [pgid] is `null`.
  Future<void> track(String jobId, int ordinal, int? pgid) {
    final key = '$jobId/$ordinal';
    if (pgid == null) {
      if (_groups.remove(key) == null) return _tail;
    } else {
      _groups[key] = pgid;
    }
    return _tail = _tail.then((_) => _save());
  }

  /// Stops every group an earlier run recorded and forgets them. Returns how
  /// many it signalled (the ones still alive).
  Future<int> reap(ProcessGroupKiller killer) async {
    var signalled = 0;
    if (_file.existsSync()) {
      try {
        final recorded = jsonDecode(await _file.readAsString());
        if (recorded is Map<String, dynamic>) {
          for (final pgid in recorded.values) {
            if (pgid is int) {
              await killer.stop(pgid);
              signalled++;
            }
          }
        }
      } on FormatException {
        // A half-written file from the crash: nothing trustworthy in it.
      }
      _file.deleteSync();
    }
    _groups.clear();
    return signalled;
  }

  Future<void> _save() async {
    if (_groups.isEmpty) {
      if (_file.existsSync()) _file.deleteSync();
      return;
    }
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(_groups));
    await temporary.rename(_file.path);
  }
}
