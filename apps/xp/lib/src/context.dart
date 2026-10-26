import 'dart:async';
import 'dart:io' as io;

import 'package:mason_logger/mason_logger.dart';
import 'package:xp/src/config/client_secret_store.dart';
import 'package:xp/src/config/token_vault.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/secret_prompt.dart';
import 'package:xp/src/update/update_check.dart';
import 'package:xp_client/xp_client.dart';

/// Makes the client for a [Connection].
typedef ClientFactory = XpClient Function(Connection connection);

/// The URL of the `origin` of the git repository the current folder is in,
/// or `null` outside one.
typedef CurrentRemote = Future<String?> Function();

Future<String?> _noRemote() async => null;

/// The `origin` of the current folder, as `git remote get-url origin` says.
Future<String?> gitOrigin() async {
  try {
    final result = await io.Process.run('git', const [
      'remote',
      'get-url',
      'origin',
    ]);
    final url = '${result.stdout}'.trim();
    return result.exitCode == 0 && url.isNotEmpty ? url : null;
  } on io.ProcessException {
    return null;
  }
}

/// What the commands of `xp` run against: where they print, where their
/// settings are, how they reach the engine. Tests pass fakes.
class XpContext {
  /// Creates a context.
  const new({
    required this.logger,
    required this.config,
    required this.environment,
    required this.clientFactory,
    required this.updateCheck,
    required this.stdin,
    required this.stdout,
    this.logIdle = const Duration(milliseconds: 750),
    this.secretPrompt = const TerminalSecretPrompt(),
    this.pollInterval = const Duration(seconds: 2),
    this.ansi = false,
    this.currentRemote = _noRemote,
  });

  /// The context of the real process.
  ///
  /// [environment] defaults to the real one; tests pass their own.
  factory system({Logger? logger, Map<String, String>? environment}) {
    final env = environment ?? io.Platform.environment;
    final directory = XpConfig.directoryFor(env, env['HOME'] ?? '');
    return XpContext(
      logger: logger ?? Logger(),
      environment: env,
      config: XpConfig(
        directory: directory,
        environment: env,
        openVault: () => SecretStoreTokenVault(
          createClientSecretStore(
            configDir: directory,
            environment: env,
            operatingSystem: io.Platform.operatingSystem,
          ),
        ),
      ),
      clientFactory: (connection) =>
          XpClient(baseUrl: connection.url, token: connection.token),
      updateCheck: UpdateCheck.system(directory, env),
      stdin: io.stdin,
      stdout: io.stdout,
      ansi: io.stdout.hasTerminal && io.stdout.supportsAnsiEscapes,
      currentRemote: gitOrigin,
    );
  }

  /// Where output goes.
  final Logger logger;

  /// The settings and tokens.
  final XpConfig config;

  /// The environment variables.
  final Map<String, String> environment;

  /// Makes a client of the engine.
  final ClientFactory clientFactory;

  /// Looks for a newer release.
  final UpdateCheck updateCheck;

  /// Standard input, which `xp mcp` reads its requests from and the
  /// `--*-stdin` options of `xp credentials` read a secret from.
  final Stream<List<int>> stdin;

  /// Standard output, which `xp mcp` writes its answers to.
  final StreamSink<List<int>> stdout;

  /// How long `xp logs` (without `-f`) waits for another line before it takes
  /// the log to be complete.
  final Duration logIdle;

  /// Asks the person at the terminal for a secret (`xp credentials add`).
  final SecretPrompt secretPrompt;

  /// How long a command that waits for a run looks again.
  final Duration pollInterval;

  /// Whether the output is a terminal that shows colours: states are
  /// coloured then.
  final bool ansi;

  /// The `origin` of the current folder, which names the project a command
  /// is about when it is left out.
  final CurrentRemote currentRemote;
}
