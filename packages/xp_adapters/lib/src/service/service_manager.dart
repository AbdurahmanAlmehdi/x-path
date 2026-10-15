import 'package:xp_adapters/src/service/launchd_service.dart';
import 'package:xp_adapters/src/service/service_definition.dart';
import 'package:xp_adapters/src/service/systemd_service.dart';
import 'package:xp_engine/xp_engine.dart';

/// The service manager could not do what was asked. The message says what to
/// do about it.
class ServiceException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong and how to fix it.
  final String message;

  @override
  String toString() => 'ServiceException: $message';
}

/// What an install wrote and started.
class ServiceInstallation {
  /// Creates the result.
  const new({required this.path, this.notes = const []});

  /// The property list or the unit file that was written.
  final String path;

  /// Things the owner should know, one sentence each.
  final List<String> notes;
}

/// Where a service is, as its manager sees it.
class ServiceStatus {
  /// Creates the status.
  const new({
    required this.path,
    required this.installed,
    required this.loaded,
    required this.running,
    this.pid,
    this.detail,
  });

  /// Where the property list or unit file is (or would be).
  final String path;

  /// Whether that file exists.
  final bool installed;

  /// Whether the manager knows the service (loaded into launchd, enabled in
  /// systemd).
  final bool loaded;

  /// Whether the service runs now.
  final bool running;

  /// The process id of the service, while it runs.
  final int? pid;

  /// What the manager says about its state, for example `active (running)` or
  /// `last exit code 78`.
  final String? detail;
}

/// A service manager of this machine: launchd on macOS, systemd on Linux.
///
/// Every call goes through the [ProcessRunner] port; the files go where the
/// manager looks for them (`~/Library/LaunchAgents`,
/// `~/.config/systemd/user`), or where the implementation was told to.
abstract interface class ServiceManager {
  /// The manager of [operatingSystem] (`macos` or `linux`).
  ///
  /// [home] is the home directory and [user] the name of the user the service
  /// runs as. Throws a [ServiceException] for another system.
  factory forPlatform({
    required String operatingSystem,
    required ProcessRunner runner,
    required String home,
    required String user,
    ServiceScope scope = ServiceScope.user,
  }) {
    switch (operatingSystem) {
      case 'macos':
        if (scope == ServiceScope.system) {
          throw const ServiceException(
            'On macOS the service is a LaunchAgent of the user '
            '(--system is for Linux).',
          );
        }
        return LaunchdService(runner: runner, home: home);
      case 'linux':
        return SystemdService(
          runner: runner,
          home: home,
          user: user,
          scope: scope,
        );
      default:
        throw ServiceException(
          'Services are supported on macOS (launchd) and Linux (systemd), not '
          'on $operatingSystem.',
        );
    }
  }

  /// Writes the service and starts it. An installed service is replaced.
  ///
  /// With [force] a service of the same name that something else registered
  /// (on macOS, the XPath app) is replaced too.
  Future<ServiceInstallation> install(
    ServiceDefinition definition, {
    bool force = false,
  });

  /// Stops the service and removes it. Returns whether there was a service
  /// file to remove.
  Future<bool> uninstall(ServiceDefinition definition);

  /// Where the service is.
  Future<ServiceStatus> status(ServiceDefinition definition);
}
