import 'package:xp_adapters/src/service/service_definition.dart';

/// One word of a command line, quoted the way systemd reads it when it has to
/// be: in double quotes, with `"` and `\` escaped.
String _word(String text) {
  if (text.isNotEmpty && !RegExp(r'''[\s"'\\]''').hasMatch(text)) return text;
  return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// The systemd unit for [definition].
///
/// - `Restart=on-failure` starts it again when it exits with a failure or is
///   killed, not when it ends with 0 (a drain, a stop). The exit code a runner
///   uses to ask for a restart after an update is a failure code. Exit codes
///   in `noRestartExitCodes` are left alone (`RestartPreventExitStatus=`).
/// - `KillMode=mixed` sends the stop signal to the main process only (it
///   drains, or shuts down) and kills what is left, the processes of
///   running steps, when `TimeoutStopSec=` ran out.
/// - The master key credential, if there is one, is `LoadCredentialEncrypted=`
///   (written by `systemd-creds encrypt`) or `LoadCredential=` (the plain
///   key), under the name the secrets file reads, D-07.
/// - A [ServiceScope.user] unit is wanted by `default.target`, a
///   [ServiceScope.system] one by `multi-user.target` and runs as `runAs`.
///
/// The values are written as they are: `%` and `$` are systemd's own markup.
/// For a machine's real values use [ServiceDefinition.escapedForSystemd].
String renderSystemdUnit(
  ServiceDefinition definition, {
  required ServiceScope scope,
}) {
  final environment = {'PATH': definition.path, ...definition.environment};
  final credential = definition.credential;
  final working = definition.workingDirectory;
  final runAs = definition.runAs;
  final wantedBy = scope == ServiceScope.user
      ? 'default.target'
      : 'multi-user.target';
  final out = StringBuffer()
    ..writeln('[Unit]')
    ..writeln('Description=${definition.description}')
    ..writeln('Documentation=https://xpath.abdurahman.ly')
    ..writeln('After=network-online.target')
    ..writeln('Wants=network-online.target')
    ..writeln()
    ..writeln('[Service]')
    ..writeln('Type=simple')
    ..write('ExecStart=')
    ..writeln(
      [definition.executable, ...definition.arguments].map(_word).join(' '),
    );
  for (final entry in environment.entries) {
    out.writeln('Environment=${_word('${entry.key}=${entry.value}')}');
  }
  if (credential != null) {
    out.writeln(
      '${credential.encrypted ? 'LoadCredentialEncrypted' : 'LoadCredential'}='
      '${credential.name}:${credential.path}',
    );
  }
  if (working != null) out.writeln('WorkingDirectory=$working');
  if (scope == ServiceScope.system && runAs != null) {
    out.writeln('User=$runAs');
  }
  out
    ..writeln('Restart=on-failure')
    ..writeln('RestartSec=5');
  if (definition.noRestartExitCodes.isNotEmpty) {
    out.writeln(
      'RestartPreventExitStatus=${definition.noRestartExitCodes.join(' ')}',
    );
  }
  out
    ..writeln('KillMode=mixed')
    ..writeln('TimeoutStopSec=${definition.stopTimeoutSeconds}')
    ..writeln()
    ..writeln('[Install]')
    ..writeln('WantedBy=$wantedBy');
  return out.toString();
}
