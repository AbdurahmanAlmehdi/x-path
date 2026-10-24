import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/command_runner.dart';
import 'package:xp/src/config/token_vault.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/secret_prompt.dart';
import 'package:xp/src/update/update_check.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// A logger that keeps what it is told, split by stream.
class RecordingLogger extends Logger {
  final infos = <String>[];
  final errors = <String>[];
  final warnings = <String>[];
  final successes = <String>[];
  final details = <String>[];

  @override
  void info(String? message, {LogStyle? style}) => infos.add('$message');

  @override
  void err(String? message, {LogStyle? style}) => errors.add('$message');

  @override
  void warn(String? message, {String tag = 'WARN', LogStyle? style}) =>
      warnings.add('$message');

  @override
  void detail(String? message, {LogStyle? style}) => details.add('$message');

  @override
  void success(String? message, {LogStyle? style}) => successes.add('$message');

  /// Everything printed to standard output, one line per entry.
  String get out => infos.join('\n');
}

class MockXpClient extends Mock implements XpClient {
  @override
  void close() => closed++;

  int closed = 0;
}

class MemoryTokenVault implements TokenVault {
  final tokens = <DeviceTokenKind, String>{};
  Exception? failWith;

  @override
  Future<String?> read(DeviceTokenKind kind) async {
    if (failWith case final error?) throw error;
    return tokens[kind];
  }

  @override
  Future<void> write(DeviceTokenKind kind, String token) async {
    if (failWith case final error?) throw error;
    tokens[kind] = token;
  }
}

/// A terminal that answers the questions it is asked from [answers], in
/// order, and keeps the questions.
class FakeSecretPrompt implements SecretPrompt {
  @override
  bool interactive = false;

  final answers = <String>[];
  final questions = <String>[];

  @override
  String ask(String question, {bool secret = true}) {
    questions.add(question);
    return answers.removeAt(0);
  }
}

class FakeUpdateCheck implements UpdateCheck {
  String? newer;
  int calls = 0;

  @override
  Future<String?> newerVersion() async {
    calls++;
    return newer;
  }
}

/// Everything a command test needs: a context whose client is a mock, a
/// recording logger, a temporary config folder.
class TestEnv {
  new({Map<String, String>? environment}) {
    directory = Directory.systemTemp.createTempSync('xp_test');
    this.environment = {
      engineUrlVariable: 'http://engine:7480',
      tokenVariable: 'cli-token',
      mcpTokenVariable: 'mcp-token',
      ...?environment,
    };
    config = XpConfig(
      directory: directory.path,
      environment: this.environment,
      openVault: () => vault,
    );
    context = XpContext(
      logger: logger,
      config: config,
      environment: this.environment,
      clientFactory: (connection) {
        connections.add(connection);
        return client;
      },
      updateCheck: update,
      stdin: stdin.stream,
      stdout: stdout,
      logIdle: const Duration(milliseconds: 50),
      secretPrompt: prompt,
    );
    runner = XpCommandRunner(context: context);
  }

  late final Directory directory;
  late final Map<String, String> environment;
  late final XpConfig config;
  late final XpContext context;
  late final XpCommandRunner runner;
  final logger = RecordingLogger();
  final client = MockXpClient();
  final vault = MemoryTokenVault();
  final update = FakeUpdateCheck();
  final prompt = FakeSecretPrompt();
  final connections = <Connection>[];
  final stdin = StreamController<List<int>>();
  final stdoutController = StreamController<List<int>>();
  StreamSink<List<int>> get stdout => stdoutController.sink;

  Future<int> run(List<String> arguments) => runner.run(arguments);

  /// Runs the command and returns what it printed.
  Future<int> runOk(List<String> arguments) async {
    final code = await run(arguments);
    expect(code, 0, reason: logger.errors.join('\n'));
    return code;
  }

  void dispose() => directory.deleteSync(recursive: true);
}

/// Registers the values mocktail needs for `any()` of the request types.
void registerFallbacks() {
  registerFallbackValue(const AddProjectRequest());
  registerFallbackValue(const DispatchRequest());
  registerFallbackValue(const CreateWorkflowRequest(name: 'n', yaml: 'y'));
  registerFallbackValue(const UpdateWorkflowRequest());
  registerFallbackValue(const FreeSpaceRequest());
  registerFallbackValue(const RetentionSettings());
  registerFallbackValue(const ProjectGates({}));
  registerFallbackValue(const ProfileEdits());
  registerFallbackValue(ReleaseStore.apple);
  registerFallbackValue(StoreState.live);
  registerFallbackValue(
    const CreateCredentialRequest(
      name: 'n',
      kind: CredentialKind.slack,
      material: {},
    ),
  );
  registerFallbackValue(const ReplaceCredentialRequest({}));
  registerFallbackValue(const AssignCredentialRequest(credentialId: 'crd_0'));
  registerFallbackValue(CredentialKind.slack);
}
