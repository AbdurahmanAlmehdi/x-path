import 'dart:async';

/// Runs actions one after the other per key, in the order they were asked.
///
/// The runner hub uses one per job, so that a heartbeat, a report of the
/// runner, a cancel and the sweep for lapsed leases never interleave on the
/// same job.
class SerialQueues {
  final _tails = <String, Future<void>>{};

  /// Runs [action] when the actions asked before for [key] are done, and
  /// returns what it returns. A failing action fails its own call only.
  Future<T> run<T>(String key, Future<T> Function() action) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = Completer<T>();
    late final Future<void> tail;
    tail = previous.then((_) async {
      try {
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        if (identical(_tails[key], tail)) unawaited(_tails.remove(key));
      }
    });
    _tails[key] = tail;
    return result.future;
  }

  /// How many keys have actions waiting or running.
  int get busyKeys => _tails.length;
}
