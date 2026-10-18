import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// A command that groups subcommands, for example `xp projects`.
class XpGroup extends Command<int> {
  /// Creates the group.
  new(
    this._context,
    this.name,
    this.description,
    List<Command<int>> commands, {
    this.aliases = const [],
  }) {
    commands.forEach(addSubcommand);
  }

  final XpContext _context;

  @override
  final String name;

  @override
  final String description;

  @override
  final List<String> aliases;

  @override
  void printUsage() => _context.logger.info(usage);
}

/// A command that talks to the engine with the `cli` token.
///
/// The base class connects, turns the failures every command can meet into a
/// message and an exit code (see [XpExit]) and closes the client. A subclass
/// implements [execute].
abstract class XpCommand extends Command<int> {
  /// Creates the command.
  new(this.context);

  /// What the command runs against.
  final XpContext context;

  /// Where output goes.
  Logger get logger => context.logger;

  /// Whether the user asked for JSON output (`--json`).
  bool get asJson => globalResults?['json'] == true;

  /// What the command does with a client of the engine. Returns the exit
  /// code.
  Future<int> execute(XpClient client);

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run() => guarded(logger, () async {
    final connection = await context.config.connection(DeviceTokenKind.cli);
    final client = context.clientFactory(connection);
    try {
      return await execute(client);
    } finally {
      client.close();
    }
  });

  /// The arguments after the options, which must be exactly [names].
  List<String> positionals(List<String> names) {
    final rest = argResults!.rest;
    if (rest.length < names.length) {
      usageException('Missing <${names[rest.length]}>.');
    }
    if (rest.length > names.length) {
      usageException('Unexpected "${rest[names.length]}".');
    }
    return rest;
  }

  /// Prints [value] as JSON, or [human] as text when the user did not ask
  /// for JSON.
  void emit(Object? value, String Function() human) =>
      logger.info(asJson ? prettyJson(value) : human());
}

/// A message for an error of the engine: what it said, and for the cases a
/// person can fix, what to do.
String describeApiError(ApiException error) => switch (error.code) {
  ApiErrorCode.unauthorized =>
    '${error.message} Run: xp connect <url> --token <token>',
  ApiErrorCode.forbidden => 'Not allowed with this token: ${error.message}',
  _ => error.message,
};

/// Runs [body] and turns the failures every command can meet into a message
/// on [logger] and an exit code (see [XpExit]).
Future<int> guarded(Logger logger, Future<int> Function() body) async {
  try {
    return await body();
  } on NotConnectedException catch (error) {
    logger.err(error.message);
    return XpExit.config;
  } on ReferenceException catch (error) {
    logger.err(error.message);
    return error.notFound ? XpExit.notFound : XpExit.usage;
  } on ApiException catch (error) {
    logger.err(describeApiError(error));
    return XpExit.forApi(error);
  } on ConnectionException catch (error) {
    logger.err(error.message);
    return XpExit.unavailable;
  } on DownloadException catch (error) {
    logger.err(error.message);
    return XpExit.failed;
  }
}
