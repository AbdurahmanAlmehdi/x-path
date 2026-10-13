import 'dart:io';

import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/server/xpd_server.dart';
import 'package:xpd/src/version.dart';

/// The port `xpd serve` listens on unless told otherwise.
const defaultPort = 7480;

/// `xpd serve`: runs the engine until SIGINT or SIGTERM.
class ServeCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'host',
        help:
            'Address to listen on. Anything but a loopback address exposes '
            'the engine to the network, without encryption.',
        defaultsTo: '127.0.0.1',
      )
      ..addOption(
        'port',
        help: 'Port to listen on. 0 picks a free port.',
        defaultsTo: '$defaultPort',
      );
  }

  @override
  String get name => 'serve';

  @override
  String get description => 'Run the engine.';

  @override
  Future<int> run() async {
    final host = argResults!['host'] as String;
    final port = int.tryParse(argResults!['port'] as String);
    if (port == null || port < 0 || port > 65535) {
      usageException('--port must be a number from 0 to 65535.');
    }
    final isLoopback =
        host == 'localhost' ||
        (InternetAddress.tryParse(host)?.isLoopback ?? false);
    if (!isLoopback) {
      context.err.writeln(
        'warning: $host is not a loopback address; anyone who can reach it '
        'can try device tokens, and traffic is not encrypted.',
      );
    }

    final directory = dataDirectory;
    return await withDatabase((database) async {
      const runner = IoProcessRunner();
      final secrets = createSecretStore(
        runner: runner,
        dataDir: directory,
        operatingSystem: context.operatingSystem,
        environment: context.environment,
      );
      final github = HttpGitHubClient(secrets: secrets);
      final events = SqliteEventLog(
        database: database,
        clock: const SystemClock(),
      );
      final server = await XpdServer.start(
        tokens: TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ),
        events: events,
        projects: ProjectService(
          repository: SqliteProjectRepository(database),
          github: github,
          git: CliGitService(
            runner: runner,
            secrets: secrets,
            dataDir: directory,
          ),
          scanner: const ProjectScanner(),
          sources: DirectoryScanSource.new,
          runner: runner,
          events: events,
          clock: const SystemClock(),
        ),
        clock: const SystemClock(),
        engineVersion: packageVersion,
        host: host,
        port: port,
        onError: (error, stackTrace) =>
            context.err.writeln('error: $error\n$stackTrace'),
      );
      context.out.writeln('xpd listening on ${server.uri}');

      await context.shutdown.first;
      context.out.writeln('xpd shutting down');
      await server.close();
      github.close();
      return 0;
    });
  }
}
