import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/service/xpd_service.dart';

/// The base of the commands that manage the engine's service: `--system`
/// picks the system unit on Linux, and a failure of the service manager is
/// an error message and exit code 1.
abstract class ServiceCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'system',
      negatable: false,
      help:
          'Linux: manage the system unit in /etc/systemd/system instead of '
          'the user unit (needs root).',
    );
  }

  /// The scope the flags ask for.
  ServiceScope get scope =>
      argResults!.flag('system') ? ServiceScope.system : ServiceScope.user;

  /// The service manager of this machine.
  ServiceManager get manager =>
      context.serviceManager?.call(scope) ??
      ServiceManager.forPlatform(
        operatingSystem: context.operatingSystem,
        runner: context.processes,
        home: context.environment['HOME'] ?? '',
        user:
            context.environment['USER'] ?? context.environment['LOGNAME'] ?? '',
        scope: scope,
      );

  /// Runs [action], and turns a [ServiceException] into an error message and
  /// exit code 1.
  Future<int> guarded(Future<int> Function() action) async {
    try {
      return await action();
    } on ServiceException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }
  }
}

/// `xpd install-service`: keeps `xpd serve` running as a LaunchAgent (macOS,
/// `ly.abdurahman.xpath.xpd`) or a systemd unit (Linux).
///
/// The XPath app registers the bundled `xpd` under the same label with
/// `SMAppService`. When the app is installed, the app owns the service and
/// this command is not needed; it is the way to run the engine without the
/// app (a Mac mini with the CLI only, a Linux server). It refuses to take a
/// label over that another registration owns, unless told with `--force`.
class InstallServiceCommand extends ServiceCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'executable',
        help:
            'The xpd to run (default: the xpd that runs this command, which '
            'must be in an installed bundle).',
        valueHelp: 'path',
      )
      ..addOption(
        'host',
        help: 'Passed to `xpd serve --host`.',
        valueHelp: 'address',
      )
      ..addOption(
        'port',
        help: 'Passed to `xpd serve --port`.',
        valueHelp: 'port',
      )
      ..addOption(
        'slots',
        help: 'Passed to `xpd serve --slots`.',
        valueHelp: 'n',
      )
      ..addOption(
        'path',
        help:
            'The PATH of the service (default: Homebrew, ~/.shorebird, '
            '~/.pub-cache, ~/fvm and the system directories). launchd and '
            'systemd start services with a short PATH that finds none of '
            'gh, fvm and shorebird.',
        valueHelp: 'dir:dir',
      )
      ..addOption(
        'run-as',
        help: 'With --system: the user the engine runs as (User=).',
        valueHelp: 'user',
      )
      ..addOption(
        'master-key-credential',
        help:
            'Linux: a file made by `systemd-creds encrypt`; systemd decrypts '
            'it and hands the master key to the engine '
            '(LoadCredentialEncrypted=$masterKeyCredentialName:<file>).',
        valueHelp: 'file',
      )
      ..addOption(
        'master-key-credential-plain',
        help:
            'Linux: a file with the 32-byte master key; systemd hands it to '
            'the engine (LoadCredential=$masterKeyCredentialName:<file>). '
            'Without either option the engine keeps master.key in its data '
            'directory (mode 600).',
        valueHelp: 'file',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'macOS: take over a label that the XPath app registered.',
      );
  }

  @override
  String get name => 'install-service';

  @override
  String get description =>
      'Keep xpd running: a LaunchAgent on macOS, a systemd unit on Linux.';

  @override
  Future<int> run() => guarded(() async {
    final results = argResults!;
    final executable = _executable();
    final isMacOS = context.operatingSystem == 'macos';
    final encrypted = results.option('master-key-credential');
    final plain = results.option('master-key-credential-plain');
    if (encrypted != null && plain != null) {
      usageException(
        'Give --master-key-credential or --master-key-credential-plain, not '
        'both.',
      );
    }
    if (isMacOS && (encrypted != null || plain != null)) {
      usageException(
        "The master key credentials are systemd's. On macOS the secrets "
        'are in the Keychain.',
      );
    }
    final runAs = results.option('run-as');
    if (scope == ServiceScope.system && runAs == null) {
      usageException(
        'A system unit runs as a user of its own: give --run-as <user>.',
      );
    }
    if (scope == ServiceScope.user && runAs != null) {
      usageException('--run-as is for --system.');
    }
    final directory = p.absolute(dataDirectory);
    final home = context.environment['HOME'] ?? '';
    final definition = XpdService.definition(
      executable: executable,
      arguments: [
        'serve',
        '--data-dir',
        directory,
        for (final option in ['host', 'port', 'slots'])
          if (results.option(option) case final value?) ...['--$option', value],
      ],
      path:
          results.option('path') ??
          defaultServicePath(
            home: home,
            operatingSystem: context.operatingSystem,
          ),
      logDirectory: isMacOS ? p.join(directory, 'service-logs') : null,
      credential: switch ((encrypted, plain)) {
        (final file?, _) => ServiceCredential(
          name: masterKeyCredentialName,
          path: p.absolute(file),
          encrypted: true,
        ),
        (_, final file?) => ServiceCredential(
          name: masterKeyCredentialName,
          path: p.absolute(file),
          encrypted: false,
        ),
        _ => null,
      },
      runAs: runAs,
    );
    final installed = await manager.install(
      definition,
      force: results.flag('force'),
    );
    context.out
      ..writeln(
        'Installed the xpd service ($xpdServiceLabel) in ${installed.path}.',
      )
      ..writeln('It runs $executable and keeps its data in $directory.');
    installed.notes.forEach(context.out.writeln);
    context.out.writeln('Check it with: xpd service-status');
    return 0;
  });

  /// The xpd the service runs: `--executable`, else the one running now, which
  /// must be an installed bundle (`.../bin/xpd`) and not `dart run`.
  String _executable() {
    final given = argResults!.option('executable');
    if (given != null) {
      if (!p.isAbsolute(given)) {
        usageException('--executable must be an absolute path.');
      }
      return given;
    }
    final running = context.executable;
    if (p.basename(running) != 'xpd') {
      usageException(
        running.isEmpty
            ? 'Cannot tell where xpd is installed: give --executable <path>.'
            : '$running is not an installed xpd (the bundle has bin/xpd): '
                  'run this command from the installed xpd, or give '
                  '--executable <path>.',
      );
    }
    return running;
  }
}

/// `xpd uninstall-service`: stops the service and removes it.
class UninstallServiceCommand extends ServiceCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'uninstall-service';

  @override
  String get description => 'Stop the xpd service and remove it.';

  @override
  Future<int> run() => guarded(() async {
    final removed = await manager.uninstall(_identity);
    context.out.writeln(
      removed
          ? 'Stopped and removed the xpd service ($xpdServiceLabel). The '
                'data directory ${p.absolute(dataDirectory)} is untouched.'
          : 'There is no xpd service to remove.',
    );
    return 0;
  });
}

/// `xpd service-status`: where the service is.
class ServiceStatusCommand extends ServiceCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'service-status';

  @override
  String get description => 'Show whether the xpd service is installed and up.';

  @override
  Future<int> run() => guarded(() async {
    final status = await manager.status(_identity);
    context.out
      ..writeln('xpd service ($xpdServiceLabel): ${_summary(status)}')
      ..writeln('  file:   ${status.path}');
    final detail = status.detail;
    if (detail != null) context.out.writeln('  state:  $detail');
    final pid = status.pid;
    if (pid != null) context.out.writeln('  pid:    $pid');
    return status.running ? 0 : 1;
  });

  String _summary(ServiceStatus status) {
    if (status.running) return 'running';
    if (!status.installed) return 'not installed';
    return status.loaded ? 'installed, not running' : 'installed, not loaded';
  }
}

/// A definition that names the service and nothing else: enough to find it to
/// remove it or ask for its status.
final ServiceDefinition _identity = XpdService.definition(
  executable: '',
  arguments: const [],
  path: '',
);
