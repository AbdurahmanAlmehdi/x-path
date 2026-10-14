/// Where a service runs: in the session of one user, or for the machine.
enum ServiceScope {
  /// A user service: a LaunchAgent on macOS, `systemctl --user` on Linux.
  user,

  /// A system service (Linux only): a unit in `/etc/systemd/system` that runs
  /// as a user of its own.
  system,
}

/// A secret the service manager hands to the service as a file, for the
/// master key of the secrets file on Linux (D-07).
///
/// systemd puts it in `$CREDENTIALS_DIRECTORY/<name>`; the engine and the
/// runner read `xpath-master-key` from there.
class ServiceCredential {
  /// Creates the credential.
  const new({required this.name, required this.path, required this.encrypted});

  /// The name of the credential, the file name under
  /// `$CREDENTIALS_DIRECTORY`.
  final String name;

  /// The file that holds it.
  final String path;

  /// Whether the file is encrypted by `systemd-creds encrypt`
  /// (`LoadCredentialEncrypted=`), else it is the plain key
  /// (`LoadCredential=`).
  final bool encrypted;
}

/// What a service runs and how its manager keeps it running.
///
/// One definition renders a LaunchAgent property list
/// (`renderLaunchAgentPlist`) and a systemd unit (`renderSystemdUnit`).
class ServiceDefinition {
  /// Creates the definition.
  const new({
    required this.label,
    required this.unitName,
    required this.description,
    required this.executable,
    required this.arguments,
    required this.path,
    required this.logName,
    this.environment = const {},
    this.logDirectory,
    this.workingDirectory,
    this.stopTimeoutSeconds = 30,
    this.credential,
    this.runAs,
    this.noRestartExitCodes = const [],
  });

  /// The launchd label, for example `ly.abdurahman.xpath.xpd` (ADR 0005). The
  /// property list is `<label>.plist`.
  final String label;

  /// The systemd unit, without `.service`, for example `xpd`.
  final String unitName;

  /// One line that says what the service is.
  final String description;

  /// The absolute path of the program.
  final String executable;

  /// The arguments of the program.
  final List<String> arguments;

  /// The `PATH` of the service. launchd and systemd start services with a
  /// short one that finds neither `gh`, `fvm`, `shorebird` nor Homebrew.
  final String path;

  /// The base name of the log files, `<logName>.out.log` and
  /// `<logName>.err.log` (macOS).
  final String logName;

  /// The environment variables besides `PATH`.
  final Map<String, String> environment;

  /// The folder of the log files on macOS (launchd has no journal), or `null`
  /// to leave the output to launchd.
  final String? logDirectory;

  /// The working directory, or `null` for the manager's.
  final String? workingDirectory;

  /// How long the manager waits for the service to stop before it kills it.
  final int stopTimeoutSeconds;

  /// The master key credential (Linux), or `null`.
  final ServiceCredential? credential;

  /// The user a system unit runs as (`User=`), or `null`.
  final String? runAs;

  /// Exit codes after which systemd does not start the service again, for
  /// example a revoked runner's.
  final List<int> noRestartExitCodes;

  /// The definition with the characters systemd reads as markup written out:
  /// `%` (specifiers) and `$` (variables) doubled. The values of a definition
  /// built for a real machine are literal text.
  ServiceDefinition escapedForSystemd() {
    String escape(String value) =>
        value.replaceAll('%', '%%').replaceAll(r'$', r'$$');
    final credential = this.credential;
    return ServiceDefinition(
      label: label,
      unitName: unitName,
      description: description,
      executable: escape(executable),
      arguments: [for (final argument in arguments) escape(argument)],
      path: escape(path),
      logName: logName,
      environment: {
        for (final entry in environment.entries) entry.key: escape(entry.value),
      },
      logDirectory: logDirectory,
      workingDirectory: workingDirectory == null
          ? null
          : escape(workingDirectory!),
      stopTimeoutSeconds: stopTimeoutSeconds,
      credential: credential == null
          ? null
          : ServiceCredential(
              name: credential.name,
              path: escape(credential.path),
              encrypted: credential.encrypted,
            ),
      runAs: runAs,
      noRestartExitCodes: noRestartExitCodes,
    );
  }
}

/// The `PATH` a service gets: Homebrew, the places the toolchain wrappers
/// live (`shorebird`, `pub`, `fvm`) and the system's own, in that order.
///
/// launchd starts a LaunchAgent with `/usr/bin:/bin:/usr/sbin:/sbin`, which
/// finds none of them. [operatingSystem] is `macos` or `linux`.
String defaultServicePath({
  required String home,
  required String operatingSystem,
}) => [
  if (operatingSystem == 'macos') ...[
    '/opt/homebrew/bin',
    '/opt/homebrew/sbin',
  ] else
    '/home/linuxbrew/.linuxbrew/bin',
  '/usr/local/bin',
  '$home/.shorebird/bin',
  '$home/.pub-cache/bin',
  '$home/fvm/default/bin',
  '/usr/bin',
  '/bin',
  '/usr/sbin',
  '/sbin',
].join(':');
