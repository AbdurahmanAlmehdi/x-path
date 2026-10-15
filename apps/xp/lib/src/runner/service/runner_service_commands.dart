import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/runner_options.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/service/runner_service.dart';
import 'package:xp/src/runner/update/runner_versions.dart';
import 'package:xp/src/version.dart';
import 'package:xp_adapters/xp_adapters.dart';

/// The base of the commands that manage the service of a runner.
abstract class _ServiceCommand extends Command<int> {
  new(this._context, this._host) {
    argParser.addFlag(
      'system',
      negatable: false,
      help:
          'Linux: manage the system unit in /etc/systemd/system instead of '
          'the user unit (needs root).',
    );
    addRunnerDataDirOption(argParser);
  }

  final XpContext _context;
  final RunnerHost _host;

  @override
  void printUsage() => _context.logger.info(usage);

  ServiceScope get _scope =>
      argResults!.flag('system') ? ServiceScope.system : ServiceScope.user;

  ServiceManager get _manager => ServiceManager.forPlatform(
    operatingSystem: _host.operatingSystem,
    runner: _host.runner,
    home: _host.home,
    user: _host.environment['USER'] ?? _host.environment['LOGNAME'] ?? '',
    scope: _scope,
  );

  Future<int> _guarded(Future<int> Function() body) async {
    try {
      return await body();
    } on ServiceException catch (error) {
      _context.logger.err(error.message);
      return XpExit.failed;
    } on FileSystemException catch (error) {
      _context.logger.err(
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
      );
      return XpExit.failed;
    }
  }

  /// A definition that names the service and nothing else.
  ServiceDefinition _identity(ArgResults results) =>
      RunnerServiceDefinition.definition(
        paths: runnerPathsOf(results, _host),
        path: '',
      );
}

/// `xp runner install-service`: keeps `xp runner start` running as a
/// LaunchAgent (macOS, `ly.abdurahman.xpath.runner`) or a systemd unit
/// (Linux).
///
/// The service runs `<data dir>/current/bin/xp`. The command installs the
/// bundle it runs from into `<data dir>/versions/<version>` and points
/// `current` at it, so that the runner can update itself in place later and go
/// back when the new version does not start (D-24). The runner must be paired
/// first.
class RunnerInstallServiceCommand extends _ServiceCommand {
  /// Creates the command.
  new(super._context, super._host) {
    argParser
      ..addOption(
        'slots',
        help: 'Passed to `xp runner start --slots`.',
        valueHelp: 'n',
      )
      ..addOption(
        'path',
        help:
            'The PATH of the service (default: Homebrew, ~/.shorebird, '
            '~/.pub-cache, ~/fvm and the system directories). launchd and '
            'systemd start services with a short PATH that finds none of '
            'git, fvm and shorebird.',
        valueHelp: 'dir:dir',
      )
      ..addOption(
        'run-as',
        help: 'With --system: the user the runner runs as (User=).',
        valueHelp: 'user',
      )
      ..addOption(
        'master-key-credential',
        help:
            'Linux: a file made by `systemd-creds encrypt` that holds the '
            'key of the credential file '
            '(LoadCredentialEncrypted=$runnerMasterKeyCredentialName:<file>). '
            'The runner has to be paired with the same key.',
        valueHelp: 'file',
      )
      ..addOption(
        'master-key-credential-plain',
        help:
            'Linux: a file with the 32-byte key '
            '(LoadCredential=$runnerMasterKeyCredentialName:<file>).',
        valueHelp: 'file',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'macOS: take over a label that something else registered.',
      );
  }

  @override
  String get name => 'install-service';

  @override
  String get description =>
      'Keep the runner running: a LaunchAgent on macOS, a systemd unit on '
      'Linux.';

  @override
  Future<int> run() => _guarded(() async {
    final logger = _context.logger;
    final results = argResults!;
    if (results.rest.isNotEmpty) {
      usageException('Unexpected "${results.rest.first}".');
    }
    final isMacOS = _host.isMacOS;
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
        "The master key credentials are systemd's. On macOS the credential "
        'of the runner is in the Keychain.',
      );
    }
    final runAs = results.option('run-as');
    if (_scope == ServiceScope.system && runAs == null) {
      usageException(
        'A system unit runs as a user of its own: give --run-as <user>.',
      );
    }
    if (_scope == ServiceScope.user && runAs != null) {
      usageException('--run-as is for --system.');
    }
    int? slots;
    final slotsText = results.option('slots');
    if (slotsText != null) {
      slots = int.tryParse(slotsText);
      if (slots == null || slots < 1) {
        usageException('--slots must be a whole number of at least 1.');
      }
    }
    final paths = runnerPathsOf(results, _host);
    if (!File(paths.identityFile).existsSync()) {
      logger.err(
        'This data directory (${paths.root}) is not paired, and a service '
        'would only fail. Run: xp runner pair --engine <url> --token <pairing '
        'token>',
      );
      return XpExit.config;
    }
    final bundle = _host.bundle;
    if (bundle == null) {
      logger.err(
        '${_host.executable.isEmpty ? 'This xp' : _host.executable} is not '
        'an installed bundle (it has bin/xp and lib/): the service runs a '
        'copy of the bundle in the data directory, so that the runner can '
        'update itself. Run this command from the installed xp.',
      );
      return XpExit.config;
    }
    final versions = RunnerVersions(paths);
    if (!versions.has(packageVersion)) {
      await versions.adopt(
        bundle: bundle,
        version: packageVersion,
        runner: _host.runner,
      );
    }
    versions.switchTo(packageVersion);

    final home = _host.home;
    final definition = RunnerServiceDefinition.definition(
      paths: paths,
      path:
          results.option('path') ??
          defaultServicePath(
            home: home,
            operatingSystem: _host.operatingSystem,
          ),
      slots: slots,
      logsToFiles: isMacOS,
      credential: switch ((encrypted, plain)) {
        (final file?, _) => ServiceCredential(
          name: runnerMasterKeyCredentialName,
          path: file,
          encrypted: true,
        ),
        (_, final file?) => ServiceCredential(
          name: runnerMasterKeyCredentialName,
          path: file,
          encrypted: false,
        ),
        _ => null,
      },
      runAs: runAs,
    );
    final installed = await _manager.install(
      definition,
      force: results.flag('force'),
    );
    logger
      ..info(
        'Installed the runner service ($runnerServiceLabel) in '
        '${installed.path}.',
      )
      ..info(
        'It runs ${paths.currentExecutable} (version $packageVersion, copied '
        'from $bundle) and updates itself to the version of its engine '
        'between jobs.',
      );
    installed.notes.forEach(logger.info);
    logger.info('Check it with: xp runner service-status');
    return XpExit.ok;
  });
}

/// `xp runner uninstall-service`: stops the service and removes it.
class RunnerUninstallServiceCommand extends _ServiceCommand {
  /// Creates the command.
  new(super._context, super._host);

  @override
  String get name => 'uninstall-service';

  @override
  String get description => 'Stop the runner service and remove it.';

  @override
  Future<int> run() => _guarded(() async {
    final logger = _context.logger;
    final removed = await _manager.uninstall(_identity(argResults!));
    logger.info(
      removed
          ? 'Stopped and removed the runner service ($runnerServiceLabel). '
                'The data directory is untouched.'
          : 'There is no runner service to remove.',
    );
    return XpExit.ok;
  });
}

/// `xp runner service-status`: where the service is.
class RunnerServiceStatusCommand extends _ServiceCommand {
  /// Creates the command.
  new(super._context, super._host);

  @override
  String get name => 'service-status';

  @override
  String get description =>
      'Show whether the runner service is installed and up.';

  @override
  Future<int> run() => _guarded(() async {
    final logger = _context.logger;
    final status = await _manager.status(_identity(argResults!));
    final summary = status.running
        ? 'running'
        : !status.installed
        ? 'not installed'
        : status.loaded
        ? 'installed, not running'
        : 'installed, not loaded';
    logger
      ..info('runner service ($runnerServiceLabel): $summary')
      ..info('  file:   ${status.path}');
    final detail = status.detail;
    if (detail != null) logger.info('  state:  $detail');
    final pid = status.pid;
    if (pid != null) logger.info('  pid:    $pid');
    return status.running ? XpExit.ok : XpExit.failed;
  });
}
