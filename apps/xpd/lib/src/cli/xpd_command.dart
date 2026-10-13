import 'package:args/command_runner.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/cli/xpd_context.dart';
import 'package:xpd/src/storage/data_directory.dart';
import 'package:xpd/src/storage/file_device_token_repository.dart';

/// A command of `xpd` that works with the engine's data directory.
abstract class XpdCommand extends Command<int> {
  /// Creates a command and gives it the `--data-dir` option.
  new(this.context) {
    argParser.addOption(
      'data-dir',
      help:
          'Where the engine keeps its files.\n'
          '(defaults to \$$dataDirectoryEnvironmentKey, then '
          '~/Library/Application Support/XPath on macOS or '
          r'$XDG_DATA_HOME/xpath elsewhere)',
      valueHelp: 'path',
    );
  }

  /// What the command runs against.
  final XpdContext context;

  @override
  void printUsage() => context.out.writeln(usage);

  /// The token service over the files in the data directory.
  TokenService openTokens() => TokenService(
    tokens: FileDeviceTokenRepository(
      resolveDataDirectory(
        option: argResults!['data-dir'] as String?,
        environment: context.environment,
        operatingSystem: context.operatingSystem,
      ),
    ),
    clock: const SystemClock(),
  );
}
