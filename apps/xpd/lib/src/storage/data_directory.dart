import 'dart:io';

import 'package:path/path.dart' as p;

/// The name of the environment variable that overrides the data directory.
const dataDirectoryEnvironmentKey = 'XPATH_DATA_DIR';

/// The data directory cannot be worked out.
class DataDirectoryException implements IOException {
  /// Creates the exception with a [message] that says how to fix it.
  const new(this.message);

  /// What is wrong and how to fix it.
  final String message;

  @override
  String toString() => message;
}

/// Where the engine keeps its files.
///
/// In order: [option] (`--data-dir`), `$XPATH_DATA_DIR`, then the platform
/// default: `~/Library/Application Support/XPath` on macOS and
/// `$XDG_DATA_HOME/xpath` (`~/.local/share/xpath`) elsewhere.
///
/// It holds the database, `xpath.db`.
String resolveDataDirectory({
  required Map<String, String> environment,
  required String operatingSystem,
  String? option,
}) {
  if (option != null && option.isNotEmpty) return option;
  final override = environment[dataDirectoryEnvironmentKey];
  if (override != null && override.isNotEmpty) return override;

  final home = environment['HOME'];
  final xdg = environment['XDG_DATA_HOME'];
  if (operatingSystem != 'macos' && xdg != null && xdg.isNotEmpty) {
    return p.join(xdg, 'xpath');
  }
  if (home == null || home.isEmpty) {
    throw const DataDirectoryException(
      'Cannot find the data directory: HOME is not set. '
      'Pass --data-dir or set $dataDirectoryEnvironmentKey.',
    );
  }
  return operatingSystem == 'macos'
      ? p.join(home, 'Library', 'Application Support', 'XPath')
      : p.join(home, '.local', 'share', 'xpath');
}
