import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/update/restarter.dart';
import 'package:xp_adapters/xp_adapters.dart';

/// The launchd label of a runner, and the name of the plist
/// (`ly.abdurahman.xpath.runner.plist`), ADR 0005.
const runnerServiceLabel = 'ly.abdurahman.xpath.runner';

/// The systemd unit of a runner, without `.service`.
const runnerUnitName = 'xp-runner';

/// The credential name the runner reads its master key from, under
/// `$CREDENTIALS_DIRECTORY` (D-07).
const runnerMasterKeyCredentialName = 'xpath-master-key';

/// How long the service manager waits for a stopped runner to finish its jobs
/// before it kills them: the runner drains, and the engine takes back what is
/// killed once the lease lapses (D-08).
const runnerStopTimeoutSeconds = 600;

/// The service definition of a runner: `current/bin/xp runner start` kept
/// running by launchd or systemd.
abstract final class RunnerServiceDefinition {
  /// The definition of the service for the runner in [paths] that starts
  /// [slots] jobs at once.
  ///
  /// The service runs `current/bin/xp` of the data directory, so that an
  /// update (a new `current`) is what the next start runs (D-24). It sets
  /// [runnerManagedVariable], and [tools]: where the Android SDK and the JDK
  /// are (`ANDROID_HOME`, `JAVA_HOME`), which a service would not find
  /// otherwise. With [runnerManagedVariable] the runner exits with a restart
  /// code after an update, and the manager starts it again. systemd does not
  /// restart it after the codes of a revoked, replaced or unpaired runner.
  static ServiceDefinition definition({
    required RunnerPaths paths,
    required String path,
    int? slots,
    bool logsToFiles = false,
    ServiceCredential? credential,
    String? runAs,
    Map<String, String> tools = const {},
  }) => ServiceDefinition(
    label: runnerServiceLabel,
    unitName: runnerUnitName,
    description: 'XPath runner (xp runner)',
    executable: paths.currentExecutable,
    arguments: [
      'runner',
      'start',
      '--data-dir',
      paths.root,
      if (slots != null) ...['--slots', '$slots'],
    ],
    path: path,
    logName: 'runner',
    environment: {...tools, runnerManagedVariable: '1'},
    logDirectory: logsToFiles ? paths.serviceLogs : null,
    stopTimeoutSeconds: runnerStopTimeoutSeconds,
    credential: credential,
    runAs: runAs,
    noRestartExitCodes: const [
      XpExit.permission,
      XpExit.conflict,
      XpExit.config,
    ],
  );

  /// The definition as the reference unit
  /// `tool/release/linux/xp-runner.service` has it: a user unit in a home
  /// directory, which systemd writes as `%h`. A test keeps the file equal to
  /// what [renderSystemdUnit] makes of this.
  static ServiceDefinition get reference => definition(
    paths: const RunnerPaths('%h/.local/share/xpath/runner'),
    path: defaultServicePath(home: '%h', operatingSystem: 'linux'),
  );
}
