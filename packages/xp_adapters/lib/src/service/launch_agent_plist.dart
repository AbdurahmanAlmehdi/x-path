import 'package:xp_adapters/src/service/service_definition.dart';

/// The `ThrottleInterval` of a LaunchAgent: launchd starts a job that exits
/// again and again at most once per this many seconds.
const launchAgentThrottleSeconds = 10;

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// The property list of the LaunchAgent for [definition].
///
/// - `RunAtLoad` starts it when it is loaded (at login of the user).
/// - `KeepAlive` with `SuccessfulExit` false starts it again when it exits
///   with a failure or is killed, not when it ends with 0: a runner that was
///   asked to drain, or an engine that was stopped, stays stopped. The exit
///   code the runner uses to ask for a restart after an update is not 0.
/// - `EnvironmentVariables` carries `PATH` and the rest of the environment.
/// - Standard output and error go to files in `logDirectory`, when there is
///   one.
String renderLaunchAgentPlist(ServiceDefinition definition) {
  final environment = {'PATH': definition.path, ...definition.environment};
  final logs = definition.logDirectory;
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    )
    ..writeln('<plist version="1.0">')
    ..writeln('<dict>')
    ..writeln('  <key>Label</key>')
    ..writeln('  <string>${_xml(definition.label)}</string>')
    ..writeln('  <key>ProgramArguments</key>')
    ..writeln('  <array>');
  for (final argument in [definition.executable, ...definition.arguments]) {
    out.writeln('    <string>${_xml(argument)}</string>');
  }
  out
    ..writeln('  </array>')
    ..writeln('  <key>RunAtLoad</key>')
    ..writeln('  <true/>')
    ..writeln('  <key>KeepAlive</key>')
    ..writeln('  <dict>')
    ..writeln('    <key>SuccessfulExit</key>')
    ..writeln('    <false/>')
    ..writeln('  </dict>')
    ..writeln('  <key>ThrottleInterval</key>')
    ..writeln('  <integer>$launchAgentThrottleSeconds</integer>')
    ..writeln('  <key>ExitTimeOut</key>')
    ..writeln('  <integer>${definition.stopTimeoutSeconds}</integer>')
    ..writeln('  <key>EnvironmentVariables</key>')
    ..writeln('  <dict>');
  for (final entry in environment.entries) {
    out
      ..writeln('    <key>${_xml(entry.key)}</key>')
      ..writeln('    <string>${_xml(entry.value)}</string>');
  }
  out.writeln('  </dict>');
  final working = definition.workingDirectory;
  if (working != null) {
    out
      ..writeln('  <key>WorkingDirectory</key>')
      ..writeln('  <string>${_xml(working)}</string>');
  }
  if (logs != null) {
    out
      ..writeln('  <key>StandardOutPath</key>')
      ..writeln(
        '  <string>${_xml('$logs/${definition.logName}.out.log')}</string>',
      )
      ..writeln('  <key>StandardErrorPath</key>')
      ..writeln(
        '  <string>${_xml('$logs/${definition.logName}.err.log')}</string>',
      );
  }
  out
    ..writeln('</dict>')
    ..writeln('</plist>');
  return out.toString();
}
