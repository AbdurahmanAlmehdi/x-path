import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xpd/src/cli/xpd_context.dart';
import 'package:xpd/src/storage/data_directory.dart';
import 'package:xpd/src/storage/engine_database.dart';

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

  /// The data directory: `--data-dir`, else the environment, else the
  /// platform default.
  String get dataDirectory => resolveDataDirectory(
    option: argResults!['data-dir'] as String?,
    environment: context.environment,
    operatingSystem: context.operatingSystem,
  );

  /// Runs [action] on the engine database in the data directory and closes
  /// the database afterwards, whatever happens.
  Future<T> withDatabase<T>(
    Future<T> Function(SqliteDatabase database) action,
  ) async {
    final database = await openEngineDatabase(dataDirectory);
    try {
      return await action(database);
    } finally {
      database.close();
    }
  }
}
