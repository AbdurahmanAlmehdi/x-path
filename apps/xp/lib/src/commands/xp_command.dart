import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/error_json.dart';
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
  Future<int> run() => guarded(logger, json: asJson, () async {
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

  /// Like [positionals] for [names] that start with `project`: when the
  /// project is left out, it is the one whose repository the current folder
  /// is a clone of, if exactly one is.
  Future<List<String>> projectPositionals(
    XpClient client,
    List<String> names,
  ) async {
    final rest = argResults!.rest;
    if (rest.length == names.length - 1) {
      final project = await projectOfRemote(
        client,
        await context.currentRemote(),
      );
      if (project != null) return [project.id, ...rest];
    }
    return positionals(names);
  }

  /// Prints [value] as JSON, or [human] as text when the user did not ask
  /// for JSON.
  void emit(Object? value, String Function() human) =>
      logger.info(asJson ? prettyJson(value) : human());
}

/// What the CLI adds to an error of the engine, for the cases a person can
/// fix: the command that fixes it. The engine names no command.
String? cliHint(ApiException error) =>
    switch ((error.code, error.details['reason'])) {
      (ApiErrorCode.unauthorized, _) => 'Run: xp connect <url> --token <token>',
      (_, ErrorReason.hasRuns) =>
        'Archive it instead: xp workflows archive <project> <workflow>',
      (_, ErrorReason.archived) =>
        'Unarchive it with: xp workflows archive <project> <workflow> --undo',
      (_, ErrorReason.credentialUnassigned) =>
        'Assign one with: xp credentials assign',
      (_, ErrorReason.productionFlavor) => 'Name the flavors with --flavor.',
      _ => null,
    };

/// A message for an error of the engine: what it said, and for the cases a
/// person can fix, what to do. The issues of a workflow document come one
/// per line.
String describeApiError(ApiException error) => error.issues.isNotEmpty
    ? 'The workflow has issues:\n${describeIssues(error.issues)}'
    : [
        if (error.code == ApiErrorCode.forbidden)
          'Not allowed with this token: ${error.message}'
        else
          error.message,
        ?(cliHint(error) ?? error.hint),
      ].join(' ');

/// The lines for the issues of a workflow document, `line:column: message`
/// and the hint.
String describeIssues(List<WorkflowIssue> issues) =>
    issues.map((issue) => '  $issue').join('\n');

/// Runs [body] and turns the failures every command can meet into a message
/// on [logger] and an exit code (see [XpExit]). With [json] the message is
/// [errorJson].
Future<int> guarded(
  Logger logger,
  Future<int> Function() body, {
  bool json = false,
}) async {
  void fail(String code, String message, [String? hint]) => logger.err(
    json
        ? jsonEncode(errorJson(code, message, hint))
        : [message, ?hint].join(' '),
  );
  try {
    return await body();
  } on NotConnectedException catch (error) {
    fail('not_connected', error.message);
    return XpExit.config;
  } on ReferenceException catch (error) {
    fail(
      error.notFound ? 'not_found' : 'ambiguous',
      error.message,
      error.cliHint,
    );
    return error.notFound ? XpExit.notFound : XpExit.usage;
  } on ApiException catch (error) {
    logger.err(
      json
          ? jsonEncode(apiErrorJson(error, hint: cliHint(error)))
          : describeApiError(error),
    );
    return XpExit.forApi(error);
  } on ConnectionException catch (error) {
    fail('unreachable', error.message);
    return XpExit.unavailable;
  } on DownloadException catch (error) {
    fail('download_failed', error.message);
    return XpExit.failed;
  }
}
