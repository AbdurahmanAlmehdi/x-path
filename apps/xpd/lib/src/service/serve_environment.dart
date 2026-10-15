import 'dart:io';

import 'package:path/path.dart' as p;

/// The environment variable the LaunchAgent of `XPath.app` sets
/// (`Contents/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`) so that
/// `xpd serve` knows launchd started it.
const launchdEnvironmentKey = 'XPATH_LAUNCHD';

/// Whether launchd started the engine for the app ([launchdEnvironmentKey]
/// is `1`).
bool isLaunchedByLaunchd(Map<String, String> environment) =>
    environment[launchdEnvironmentKey] == '1';

/// The folders of the tools jobs run (`shorebird`, `pub`, `fvm`, Homebrew),
/// for the home folder [home], in the order they go on `PATH`.
List<String> toolDirectories(String home) => [
  p.join(home, '.shorebird', 'bin'),
  p.join(home, '.pub-cache', 'bin'),
  p.join(home, 'fvm', 'default', 'bin'),
  '/opt/homebrew/bin',
  '/usr/local/bin',
];

/// [environment] with the [toolDirectories] that exist ([isDirectory]) and
/// are missing from its `PATH` put in front of it.
///
/// launchd starts the app's LaunchAgent with a fixed `PATH` that cannot
/// name the home folder (a plist does not expand `~`), so the engine and
/// the processes it starts would not find `shorebird`, `fvm` or the tools
/// installed with `dart pub global activate`.
Map<String, String> withToolDirectories(
  Map<String, String> environment, {
  bool Function(String path)? isDirectory,
}) {
  final home = environment['HOME'];
  if (home == null || home.isEmpty) return environment;
  final exists = isDirectory ?? (path) => Directory(path).existsSync();
  final path = environment['PATH'] ?? '';
  final present = path.split(':').where((entry) => entry.isNotEmpty).toSet();
  final missing = [
    for (final directory in toolDirectories(home))
      if (!present.contains(directory) && exists(directory)) directory,
  ];
  if (missing.isEmpty) return environment;
  return {
    ...environment,
    'PATH': [...missing, if (path.isNotEmpty) path].join(':'),
  };
}

/// The log file of the engine that launchd started for the app:
/// `<data-dir>/service-logs/xpd.log`, beside the logs of
/// `xpd install-service`.
String serveLogPath(String dataDirectory) =>
    p.join(dataDirectory, 'service-logs', 'xpd.log');

/// A [StringSink] that appends lines to a log file, each with the UTC time
/// it was written.
class LogFileSink implements StringSink {
  new _(this._sink, this._now);

  /// Opens the log at [path] for appending. A log that has grown past
  /// [maxBytes] is moved to `<path>.1` first (replacing the one there), so
  /// the logs of an engine that runs for months stay small.
  factory open(
    String path, {
    DateTime Function() now = DateTime.now,
    int maxBytes = 10 * 1024 * 1024,
  }) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() > maxBytes) {
      file.renameSync('$path.1');
    }
    return LogFileSink._(File(path).openWrite(mode: FileMode.append), now);
  }

  final IOSink _sink;
  final DateTime Function() _now;
  final _line = StringBuffer();

  @override
  void write(Object? object) {
    final text = '$object';
    var start = 0;
    for (
      var end = text.indexOf('\n');
      end >= 0;
      end = text.indexOf('\n', start)
    ) {
      _line.write(text.substring(start, end));
      _sink.writeln('${_now().toUtc().toIso8601String()} $_line');
      _line.clear();
      start = end + 1;
    }
    _line.write(text.substring(start));
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  /// Writes what is left of the last line and closes the file.
  Future<void> close() async {
    if (_line.isNotEmpty) writeln();
    await _sink.close();
  }
}
