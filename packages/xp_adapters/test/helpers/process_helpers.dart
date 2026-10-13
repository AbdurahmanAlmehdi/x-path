import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// Whether a process with [pid] exists (`kill -0`, which sends no signal).
bool processAlive(int pid) =>
    Process.runSync('/bin/sh', ['-c', 'kill -0 $pid']).exitCode == 0;

/// The process group of [pid], as `ps` reports it.
int processGroup(int pid) => int.parse(
  (Process.runSync('ps', ['-o', 'pgid=', '-p', '$pid']).stdout as String)
      .trim(),
);

/// A masker that replaces known secrets within each piece. Its streams hold
/// back the last character of every piece, so that tests see that the
/// supervisor feeds pieces in and flushes at the end.
class LaggingMasker implements OutputMasker {
  /// Creates a masker that hides [secrets].
  new([Iterable<String> secrets = const []]) {
    secrets.forEach(add);
  }

  final _secrets = <String>[];

  /// The streams created so far.
  int streams = 0;

  @override
  void add(String secret) => _secrets.add(secret);

  @override
  StreamMasker newStream() {
    streams++;
    return _LaggingStream(_secrets);
  }
}

class _LaggingStream implements StreamMasker {
  new(this._secrets);

  final List<String> _secrets;
  var _held = '';

  @override
  String add(String piece) {
    final text = _held + piece;
    if (text.isEmpty) return '';
    _held = text.substring(text.length - 1);
    return _mask(text.substring(0, text.length - 1));
  }

  @override
  String flush() {
    final rest = _held;
    _held = '';
    return _mask(rest);
  }

  String _mask(String text) =>
      _secrets.fold(text, (masked, secret) => masked.replaceAll(secret, '***'));
}
