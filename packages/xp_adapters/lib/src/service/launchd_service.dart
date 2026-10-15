import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/src/service/launch_agent_plist.dart';
import 'package:xp_adapters/src/service/service_definition.dart';
import 'package:xp_adapters/src/service/service_manager.dart';
import 'package:xp_engine/xp_engine.dart';

/// A LaunchAgent of the user, the way macOS runs the engine and a runner on a
/// Mac (D-10): `~/Library/LaunchAgents/<label>.plist`, loaded into the
/// `gui/<uid>` domain with `launchctl bootstrap`.
///
/// The `gui` domain exists while the user is logged in (the Mac mini of D-10
/// logs in on its own, an auto-login user). The XPath app registers the
/// bundled `xpd` under the same label with `SMAppService`; this class is the
/// command-line and headless path to the same service, and refuses to replace
/// what another registration owns unless it is told to.
class LaunchdService implements ServiceManager {
  /// Creates the manager. [launchAgents] is the folder of the property lists
  /// (default `~/Library/LaunchAgents`); tests pass a temporary one.
  new({
    required this._runner,
    required String home,
    String? launchAgents,
    Future<String> Function()? uid,
  }) : launchAgents = launchAgents ?? p.join(home, 'Library', 'LaunchAgents'),
       _userIdOverride = uid;

  final ProcessRunner _runner;
  final Future<String> Function()? _userIdOverride;

  /// The folder of the property lists.
  final String launchAgents;

  /// The property list of [definition].
  String plistPath(ServiceDefinition definition) =>
      p.join(launchAgents, '${definition.label}.plist');

  @override
  Future<ServiceInstallation> install(
    ServiceDefinition definition, {
    bool force = false,
  }) async {
    final domain = 'gui/${await _uid()}';
    final target = '$domain/${definition.label}';
    final plist = plistPath(definition);
    final loaded = await _print(target);
    if (loaded != null && !force) {
      final owner = _field(loaded.stdout, 'path');
      if (owner != null && p.normalize(owner) != p.normalize(plist)) {
        throw ServiceException(
          '${definition.label} is registered already, from $owner (the '
          'XPath app does that). Use it from there, or run this command with '
          '--force to take the service over.',
        );
      }
    }
    final logs = definition.logDirectory;
    if (logs != null) Directory(logs).createSync(recursive: true);
    _write(plist, renderLaunchAgentPlist(definition));
    if (loaded != null) {
      // Unload the old definition; a failure here only means it was gone.
      await _launchctl(['bootout', target]);
    }
    final bootstrap = await _launchctl(['bootstrap', domain, plist]);
    if (bootstrap.exitCode != 0) {
      throw ServiceException(
        'launchctl bootstrap failed (exit ${bootstrap.exitCode}): '
        '${_message(bootstrap)}. A LaunchAgent loads into the login session '
        'of the user ($domain): log in on this Mac (the Mac mini of the '
        'engine logs in on its own) and run the command again.',
      );
    }
    final output =
        '$logs/${definition.logName}.out.log and '
        '${definition.logName}.err.log';
    return ServiceInstallation(
      path: plist,
      notes: [
        if (logs != null) 'Output goes to $output; launchd does not rotate it.',
      ],
    );
  }

  @override
  Future<bool> uninstall(ServiceDefinition definition) async {
    final domain = 'gui/${await _uid()}';
    // Not loaded is not an error here: the point is that it is gone.
    await _launchctl(['bootout', '$domain/${definition.label}']);
    final plist = File(plistPath(definition));
    if (!plist.existsSync()) return false;
    plist.deleteSync();
    return true;
  }

  @override
  Future<ServiceStatus> status(ServiceDefinition definition) async {
    final domain = 'gui/${await _uid()}';
    final plist = plistPath(definition);
    final installed = File(plist).existsSync();
    final printed = await _print('$domain/${definition.label}');
    if (printed == null) {
      return ServiceStatus(
        path: plist,
        installed: installed,
        loaded: false,
        running: false,
        detail: installed ? 'not loaded' : 'not installed',
      );
    }
    final state = _field(printed.stdout, 'state');
    final pid = int.tryParse(_field(printed.stdout, 'pid') ?? '');
    final lastExit = _field(printed.stdout, 'last exit code');
    return ServiceStatus(
      path: plist,
      installed: installed,
      loaded: true,
      running: state == 'running',
      pid: pid,
      detail: [
        ?state,
        if (lastExit != null) 'last exit code $lastExit',
      ].join(', '),
    );
  }

  /// The output of `launchctl print`, or `null` if the service is not loaded.
  Future<ProcessOutput?> _print(String target) async {
    final output = await _launchctl(['print', target]);
    return output.exitCode == 0 ? output : null;
  }

  Future<ProcessOutput> _launchctl(List<String> arguments) =>
      _exec('launchctl', arguments);

  Future<ProcessOutput> _exec(String program, List<String> arguments) async {
    try {
      return await _runner.run(
        program,
        arguments,
        timeout: const Duration(seconds: 30),
      );
    } on ProcessStartException catch (error) {
      throw ServiceException('Cannot run $program: ${error.message}');
    }
  }

  /// The value of the line `name = value` of a `launchctl print`.
  static String? _field(String output, String name) {
    final match = RegExp(
      '^\\s*${RegExp.escape(name)} = (.+)\$',
      multiLine: true,
    ).firstMatch(output);
    return match?.group(1)?.trim();
  }

  static String _message(ProcessOutput output) {
    final text = '${output.stderr}${output.stdout}'.trim();
    return text.isEmpty ? 'no message' : text.replaceAll('\n', ' ');
  }

  Future<String> _uid() async {
    final override = _userIdOverride;
    if (override != null) return await override();
    final output = await _exec('id', ['-u']);
    final uid = output.stdout.trim();
    if (output.exitCode != 0 || int.tryParse(uid) == null) {
      throw const ServiceException('Cannot tell the user id (id -u).');
    }
    return uid;
  }

  /// Writes [text] to [path] by way of a temporary file in the same folder, so
  /// launchd never reads half of it.
  static void _write(String path, String text) {
    File(path).parent.createSync(recursive: true);
    File('$path.partial')
      ..writeAsStringSync(text)
      ..renameSync(path);
  }
}
