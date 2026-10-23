import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Writes the comings and goings of runners to the engine log: one line per
/// connect, disconnect, change of capabilities and refused connection.
///
/// `xp_engine` stays free of logging: the hub records events and reports
/// refusals, and this turns them into lines.
class RunnerLog {
  /// Creates the log, which writes to [_out] and reads what a runner reported
  /// about itself from [_runners].
  const new(this._out, this._runners);

  final StringSink _out;
  final RunnerService _runners;

  /// Follows the runner events logged in [events] from now on.
  StreamSubscription<void> follow(EventLog events) => events
      .subscribe(after: events.head)
      .asyncMap((logged) => _write(logged.event))
      .listen(null, onError: (Object _) {});

  /// Writes that the connection of [who] was turned away, and [why].
  void refused(String who, String why) =>
      _out.writeln('refused a runner connection from $who: $why');

  Future<void> _write(EngineEvent event) async {
    switch (event) {
      case RunnerConnected():
        _out.writeln(await _connected(event));
      case RunnerDisconnected(:final name, :final reason):
        _out.writeln(
          'runner "$name" disconnected${reason == null ? '' : ' ($reason)'}',
        );
      case RunnerCapabilitiesChanged(:final name, :final from, :final to):
        _out.writeln(
          'runner "$name" now offers ${_offers(to)} (was ${_offers(from)})',
        );
      default:
        break;
    }
  }

  Future<String> _connected(RunnerConnected event) async {
    final Runner runner;
    try {
      runner = await _runners.get(event.runnerId);
    } on RunnerNotFoundException {
      return 'runner "${event.name}" connected';
    }
    final missing = runner.missing ?? const <MissingCapability>[];
    return [
      'runner "${event.name}" connected: ',
      [
        if (runner.version case final version?) 'xp $version',
        if (runner.os != null || runner.arch != null)
          [?runner.os, ?runner.arch].join(' '),
        '${event.slots} slot${event.slots == 1 ? '' : 's'}',
        _offers(event.capabilities),
      ].join(', '),
      if (missing.isNotEmpty) ' (${missing.map(_lacks).join('; ')})',
    ].join();
  }

  static String _lacks(MissingCapability missing) =>
      'no ${missing.capability}: ${missing.reason}';

  static String _offers(List<String> capabilities) =>
      capabilities.isEmpty ? 'nothing' : capabilities.join(', ');
}
