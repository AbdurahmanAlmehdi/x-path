import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:xp/src/mcp/mcp_tool.dart';

/// Serves [tools] over MCP on [input] and [output] (standard input and
/// output, one JSON-RPC message per line) until the client closes the input.
///
/// This is the only file that imports `dart_mcp`. The package is 0.x and its
/// API changes between minors (it is pinned in `pubspec.yaml`), so everything
/// else works with `McpTool`, and a change of `dart_mcp` stays in this file.
Future<void> serveMcp({
  required List<McpTool> tools,
  required Stream<List<int>> input,
  required StreamSink<List<int>> output,
  required String name,
  required String version,
  List<McpResource> resources = const [],
  String? instructions,
}) async {
  final server = _XpMcpServer(
    stdioChannel(input: input, output: output),
    tools: tools,
    resources: resources,
    name: name,
    version: version,
    instructions: instructions,
  );
  await server.done;
}

base class _XpMcpServer extends MCPServer with ToolsSupport, ResourcesSupport {
  new(
    super.channel, {
    required List<McpTool> tools,
    required List<McpResource> resources,
    required String name,
    required String version,
    super.instructions,
  }) : super.fromStreamChannel(
         implementation: Implementation(name: name, version: version),
       ) {
    for (final tool in tools) {
      registerTool(
        Tool(
          name: tool.name,
          description: tool.description,
          inputSchema: ObjectSchema.fromMap(tool.inputSchema),
          annotations: ToolAnnotations(readOnlyHint: tool.readOnly),
        ),
        (request) async {
          final result = await tool.handler(request.arguments ?? const {});
          return CallToolResult(
            content: [TextContent(text: result.text)],
            isError: result.isError,
          );
        },
      );
    }
    for (final resource in resources) {
      addResource(
        Resource(
          uri: resource.uri,
          name: resource.name,
          description: resource.description,
          mimeType: resource.mimeType,
        ),
        (request) async => ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: resource.uri,
              text: await resource.read(),
              mimeType: resource.mimeType,
            ),
          ],
        ),
      );
    }
  }
}
