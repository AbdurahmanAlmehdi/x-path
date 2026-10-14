import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/command_runner.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';

import '../../helpers/mcp_harness.dart';
import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;
  late McpHarness harness;
  late XpCommandRunner runner;

  setUp(() {
    env = TestEnv();
    harness = McpHarness();
    runner = XpCommandRunner(
      context: XpContext(
        logger: env.logger,
        config: env.config,
        environment: env.environment,
        clientFactory: env.context.clientFactory,
        updateCheck: env.update,
        stdin: harness.input,
        stdout: harness.output,
      ),
    );
  });
  tearDown(() => env.dispose());

  test(
    'serves the tools on standard input and output with the MCP token',
    () async {
      when(() => env.client.listProjects())
          .thenAnswer((_) async => [sample.project]);
      final exit = runner.run(['mcp']);

      final init = await harness.initialize();
      final result = await harness.callTool('list_projects');
      await harness.closeInput();

      expect(await exit, 0);
      expect((init['serverInfo'] as Map)['name'], 'xpath');
      expect(init['instructions'], contains('can never approve'));
      expect(
        (jsonDecode(
          ((result['content'] as List).single as Map)['text'] as String,
        ) as List<dynamic>).single,
        isA<Map<String, dynamic>>(),
      );
      // Its own token, never the token of the CLI.
      expect(env.connections.single.token, 'mcp-token');
      expect(env.client.closed, 1);
      // Standard output carries MCP and nothing else.
      expect(env.logger.infos, isEmpty);
      expect(env.logger.errors, isEmpty);
    },
  );

  test('offers no tool that approves', () async {
    final exit = runner.run(['mcp']);
    await harness.initialize();

    final answer = await harness.request('tools/list');
    await harness.closeInput();
    await exit;

    final names = [
      for (final tool in (answer['result'] as Map)['tools'] as List<dynamic>)
        (tool as Map)['name'] as String,
    ];
    expect(
      names.where((name) => name.contains('approve') || name.contains('deny')),
      isEmpty,
    );
    expect(names, contains('get_approval'));
  });

  test('without an MCP token says so on standard error and exits 78', () async {
    env = TestEnv(environment: {mcpTokenVariable: ''});
    runner = XpCommandRunner(context: env.context);

    expect(await runner.run(['mcp']), 78);

    expect(env.logger.errors.single, contains('--mcp-token'));
    expect(env.connections, isEmpty);
  });

  test('the update check never runs for it', () async {
    final exit = runner.run(['mcp']);
    await harness.initialize();
    await harness.closeInput();
    await exit;

    expect(env.update.calls, 0);
  });
}
