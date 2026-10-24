import 'dart:async';

import 'package:test/test.dart';
import 'package:xp/src/mcp/dart_mcp_adapter.dart';
import 'package:xp/src/mcp/mcp_tool.dart';

import '../../helpers/mcp_harness.dart';

void main() {
  late McpHarness harness;
  late Future<void> served;
  late List<Map<String, Object?>> calls;

  setUp(() {
    harness = McpHarness();
    calls = [];
    served = serveMcp(
      tools: [
        McpTool(
          name: 'echo',
          description: 'Repeats the text.',
          readOnly: true,
          inputSchema: {
            'type': 'object',
            'properties': {
              'text': {'type': 'string'},
            },
            'required': ['text'],
          },
          handler: (arguments) async {
            calls.add(arguments);
            return McpToolResult('said ${arguments['text']}');
          },
        ),
        McpTool(
          name: 'fail',
          description: 'Always fails.',
          inputSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
          handler: (_) async => McpToolResult.error('no luck'),
        ),
      ],
      input: harness.input,
      output: harness.output,
      name: 'xpath',
      version: '1.2.3',
      resources: [
        McpResource(
          uri: 'xpath://notes',
          name: 'Notes',
          description: 'Some notes.',
          read: () async => '{"a": 1}',
        ),
      ],
      instructions: 'Be careful.',
    );
  });

  test('introduces itself with its name, version and instructions', () async {
    final result = await harness.initialize();

    expect(result['serverInfo'], {'name': 'xpath', 'version': '1.2.3'});
    expect(result['instructions'], 'Be careful.');
    expect(result['capabilities'] as Map, contains('tools'));
    await harness.closeInput();
    await served;
  });

  test('lists the tools with their schemas and read-only hints', () async {
    await harness.initialize();

    final answer = await harness.request('tools/list');

    final tools = (answer['result'] as Map)['tools'] as List<dynamic>;
    expect(tools.map((tool) => (tool as Map)['name']), ['echo', 'fail']);
    final echo = tools.first as Map<String, dynamic>;
    expect(echo['description'], 'Repeats the text.');
    expect((echo['inputSchema'] as Map)['required'], ['text']);
    expect((echo['annotations'] as Map)['readOnlyHint'], isTrue);
    expect(
      ((tools.last as Map)['annotations'] as Map)['readOnlyHint'],
      isFalse,
    );
    await harness.closeInput();
    await served;
  });

  test('calls a tool and returns its text', () async {
    await harness.initialize();

    final result = await harness.callTool('echo', {'text': 'hi'});

    expect(calls, [
      {'text': 'hi'},
    ]);
    expect(result['isError'], isFalse);
    expect((result['content'] as List).single, {
      'type': 'text',
      'text': 'said hi',
    });
    await harness.closeInput();
    await served;
  });

  test('marks a failed call as an error', () async {
    await harness.initialize();

    final result = await harness.callTool('fail');

    expect(result['isError'], isTrue);
    expect(((result['content'] as List).single as Map)['text'], 'no luck');
    await harness.closeInput();
    await served;
  });

  test(
    'checks the arguments against the schema before the tool runs',
    () async {
      await harness.initialize();

      final result = await harness.callTool('echo');

      expect(result['isError'], isTrue);
      expect(calls, isEmpty);
      await harness.closeInput();
      await served;
    },
  );

  test('says when a tool does not exist', () async {
    await harness.initialize();

    final result = await harness.callTool('approve_approval', {
      'approval': 'apr_1',
    });

    expect(result['isError'], isTrue);
    expect(
      ((result['content'] as List).single as Map)['text'],
      contains('No tool registered'),
    );
    await harness.closeInput();
    await served;
  });

  test('lists and reads its resources', () async {
    await harness.initialize();

    final list = await harness.request('resources/list');
    final read = await harness.request('resources/read', {
      'uri': 'xpath://notes',
    });

    final resource =
        ((list['result'] as Map)['resources'] as List).single as Map;
    expect(resource['uri'], 'xpath://notes');
    expect(resource['name'], 'Notes');
    expect(resource['mimeType'], 'application/json');
    expect(((read['result'] as Map)['contents'] as List).single, {
      'uri': 'xpath://notes',
      'text': '{"a": 1}',
      'mimeType': 'application/json',
    });
    await harness.closeInput();
    await served;
  });

  test('ends when the client closes its input', () async {
    await harness.initialize();

    await harness.closeInput();

    await expectLater(served, completes);
  });
}
