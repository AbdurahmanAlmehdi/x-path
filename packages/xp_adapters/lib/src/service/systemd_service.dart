import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/src/service/service_definition.dart';
import 'package:xp_adapters/src/service/service_manager.dart';
import 'package:xp_adapters/src/service/systemd_unit.dart';
import 'package:xp_engine/xp_engine.dart';

/// A systemd unit: `~/.config/systemd/user/<name>.service` for a user
/// service (`systemctl --user`), `/etc/systemd/system/<name>.service` for a
/// system one.
///
/// The master key of the secrets file reaches the service as a systemd
/// credential (D-07), see [ServiceCredential].
class SystemdService implements ServiceManager {
  /// Creates the manager. [unitDirectory] is the folder of the unit files;
  /// tests pass a temporary one.
  new({
    required this._runner,
    required String home,
    required this._user,
    this.scope = ServiceScope.user,
    String? unitDirectory,
  }) : unitDirectory =
           unitDirectory ??
           (scope == ServiceScope.user
               ? p.join(home, '.config', 'systemd', 'user')
               : '/etc/systemd/system');

  final ProcessRunner _runner;
  final String _user;

  /// Whether the unit is a user unit or a system unit.
  final ServiceScope scope;

  /// The folder of the unit files.
  final String unitDirectory;

  /// The unit file of [definition].
  String unitPath(ServiceDefinition definition) =>
      p.join(unitDirectory, '${definition.unitName}.service');

  List<String> get _prefix => scope == ServiceScope.user ? ['--user'] : [];

  @override
  Future<ServiceInstallation> install(
    ServiceDefinition definition, {
    bool force = false,
  }) async {
    final path = unitPath(definition);
    final unit = renderSystemdUnit(
      definition.escapedForSystemd(),
      scope: scope,
    );
    try {
      Directory(unitDirectory).createSync(recursive: true);
      File('$path.partial')
        ..writeAsStringSync(unit)
        ..renameSync(path);
    } on FileSystemException catch (error) {
      throw ServiceException(
        'Cannot write $path: ${error.osError?.message ?? error.message}.'
        '${scope == ServiceScope.system ? ' A system unit needs root: run '
                  'the command with sudo.' : ''}',
      );
    }
    await _systemctl(['daemon-reload']);
    await _systemctl(['enable', '--now', '${definition.unitName}.service']);
    const lingerHint =
        'A user service stops when the user logs out. To keep it running '
        'without a login, run: sudo loginctl enable-linger';
    return ServiceInstallation(
      path: path,
      notes: [
        if (scope == ServiceScope.user && await _lingerOff())
          '$lingerHint $_user',
      ],
    );
  }

  @override
  Future<bool> uninstall(ServiceDefinition definition) async {
    final path = File(unitPath(definition));
    // A unit that is not loaded or not enabled is as good as gone.
    await _run(['disable', '--now', '${definition.unitName}.service']);
    if (!path.existsSync()) return false;
    path.deleteSync();
    await _run(['daemon-reload']);
    return true;
  }

  @override
  Future<ServiceStatus> status(ServiceDefinition definition) async {
    final path = unitPath(definition);
    final installed = File(path).existsSync();
    final output = await _run([
      'show',
      '${definition.unitName}.service',
      '--property=LoadState,ActiveState,SubState,MainPID,UnitFileState',
    ]);
    final fields = <String, String>{};
    for (final line in output.stdout.split('\n')) {
      final at = line.indexOf('=');
      if (at > 0) fields[line.substring(0, at)] = line.substring(at + 1).trim();
    }
    final active = fields['ActiveState'];
    final pid = int.tryParse(fields['MainPID'] ?? '');
    return ServiceStatus(
      path: path,
      installed: installed,
      loaded: fields['LoadState'] == 'loaded',
      running: active == 'active',
      pid: pid != null && pid > 0 ? pid : null,
      detail: output.exitCode != 0 || active == null
          ? 'unknown to systemd'
          : '$active (${fields['SubState']}), '
                '${fields['UnitFileState'] ?? 'not enabled'}',
    );
  }

  /// Whether `loginctl` says the user does not linger. A system that cannot
  /// say is taken to be one that does not.
  Future<bool> _lingerOff() async {
    try {
      final output = await _runner.run('loginctl', [
        'show-user',
        _user,
        '--property=Linger',
      ], timeout: const Duration(seconds: 10));
      return output.stdout.trim() != 'Linger=yes';
    } on Object {
      return true;
    }
  }

  /// Runs `systemctl` and fails with its message when it does.
  Future<void> _systemctl(List<String> arguments) async {
    final output = await _run(arguments);
    if (output.exitCode == 0) return;
    final text = '${output.stderr}${output.stdout}'.trim().replaceAll(
      '\n',
      ' ',
    );
    throw ServiceException(
      'systemctl ${arguments.first} failed (exit ${output.exitCode}): '
      '${text.isEmpty ? 'no message' : text}.'
      '${scope == ServiceScope.user ? ' A user service needs the user '
                'session of systemd: log in (not with su) and run the command '
                'again.' : ''}',
    );
  }

  Future<ProcessOutput> _run(List<String> arguments) async {
    try {
      return await _runner.run('systemctl', [
        ..._prefix,
        ...arguments,
      ], timeout: const Duration(seconds: 60));
    } on ProcessStartException catch (error) {
      throw ServiceException('Cannot run systemctl: ${error.message}');
    }
  }
}
