import 'package:xp_adapters/xp_adapters.dart';

/// The launchd label of the engine, and the name of the plist
/// (`ly.abdurahman.xpath.xpd.plist`), ADR 0005.
const xpdServiceLabel = 'ly.abdurahman.xpath.xpd';

/// The systemd unit of the engine, without `.service`.
const xpdUnitName = 'xpd';

/// The credential name the engine reads its master key from, under
/// `$CREDENTIALS_DIRECTORY` (D-07).
const masterKeyCredentialName = 'xpath-master-key';

/// The service definition of the engine: `xpd serve` kept running by launchd
/// or systemd.
abstract final class XpdService {
  /// The definition of the service that runs [executable] with [arguments].
  ///
  /// On macOS the output goes to files in [logDirectory], on Linux to the
  /// journal. The engine stops within 30 seconds of the stop signal: it
  /// closes its connections and leaves the jobs it runs to the recovery of
  /// the next start (ADR 0006).
  static ServiceDefinition definition({
    required String executable,
    required List<String> arguments,
    required String path,
    String? logDirectory,
    ServiceCredential? credential,
    String? runAs,
  }) => ServiceDefinition(
    label: xpdServiceLabel,
    unitName: xpdUnitName,
    description: 'XPath engine (xpd)',
    executable: executable,
    arguments: arguments,
    path: path,
    logName: 'xpd',
    logDirectory: logDirectory,
    credential: credential,
    runAs: runAs,
  );

  /// The definition as the reference unit `tool/release/linux/xpd.service`
  /// has it: a user unit in a home directory, which systemd writes as `%h`,
  /// with the master key as an encrypted credential. A test keeps the file
  /// equal to what [renderSystemdUnit] makes of this.
  static ServiceDefinition get reference => definition(
    executable: '%h/.local/lib/xpath/xpd/bin/xpd',
    arguments: const ['serve', '--data-dir', '%h/.local/share/xpath'],
    path: defaultServicePath(home: '%h', operatingSystem: 'linux'),
    credential: const ServiceCredential(
      name: masterKeyCredentialName,
      path: '%h/.config/xpath/xpath-master-key.cred',
      encrypted: true,
    ),
  );
}
