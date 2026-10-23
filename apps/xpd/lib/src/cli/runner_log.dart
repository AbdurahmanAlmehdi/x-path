import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Writes the comings and goings of runners to the engine log: one line per
/// connect, disconnect, change of capabilities and refused connection.
///
/// `xp_engine` stays free of logging: the hub records events and reports
/// refusals, and this turns them into lines.
class RunnerLog {
  /// Creates the log, which writes to [_out]; [onError] hears about a line
  /// that could not be written.
  const new(this._out, {this.onError});

  final StringSink _out;

  /// Hears about a runner event that could not be turned into a line.
  final void Function(Object error)? onError;

  /// Follows the runner events logged in [events] from now on, and reads
  /// what a runner reported about itself from [runners].
  StreamSubscription<void> follow(EventLog events, RunnerService runners) =>
      events
          .subscribe(after: events.head)
          .asyncMap((logged) => _write(logged.event, runners))
          .listen(null, onError: (Object error) => onError?.call(error));

  /// Writes that the connection of [who] was turned away, and [why].
  void refused(String who, String why) =>
      _out.writeln('refused a runner connection from $who: $why');

  Future<void> _write(EngineEvent event, RunnerService runners) async {
    switch (event) {
      case RunnerConnected():
        _out.writeln(await _connected(event, runners));
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

  Future<String> _connected(
    RunnerConnected event,
    RunnerService runners,
  ) async {
    final Runner runner;
    try {
      runner = await runners.get(event.runnerId);
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
