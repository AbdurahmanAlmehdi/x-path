import 'package:xp/src/output/format.dart';

/// The arguments of a tool call: the JSON object the agent sent.
typedef McpArguments = Map<String, Object?>;

/// What a tool answers: text for the agent to read.
class McpToolResult {
  /// Creates a result with [text].
  const new(this.text, {this.isError = false});

  /// A result that is [value] as JSON.
  factory json(Object? value, {bool isError = false}) =>
      McpToolResult(prettyJson(value), isError: isError);

  /// A result that says what went wrong.
  factory error(String message) => McpToolResult(message, isError: true);

  /// What the agent reads.
  final String text;

  /// Whether the call failed.
  final bool isError;
}

/// Does what a tool is for.
typedef McpToolHandler = Future<McpToolResult> Function(McpArguments arguments);

/// A tool `xp mcp` offers an agent, described without any MCP library: the
/// adapter (`dart_mcp_adapter.dart`) is the only place that knows one.
class McpTool {
  /// Creates a tool. [inputSchema] is a JSON Schema object.
  const new({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.readOnly = false,
  });

  /// The name the agent calls it by.
  final String name;

  /// What it does and when to use it.
  final String description;

  /// The JSON Schema of its arguments.
  final Map<String, Object?> inputSchema;

  /// Whether it only reads.
  final bool readOnly;

  /// Runs a call.
  final McpToolHandler handler;
}

/// An argument is missing or has the wrong type.
class McpArgumentError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => message;
}

/// Typed access to the [McpArguments] of one call.
class McpArgs {
  /// Wraps [values].
  const new(this.values);

  /// The raw arguments.
  final McpArguments values;

  /// The string argument [name]; it must be there.
  String string(String name) =>
      optionalString(name) ?? (throw McpArgumentError('"$name" is required.'));

  /// The string argument [name], or `null`.
  String? optionalString(String name) => switch (values[name]) {
    null => null,
    final String value => value,
    _ => throw McpArgumentError('"$name" must be a string.'),
  };

  /// The integer argument [name], or `null`.
  int? optionalInt(String name) => switch (values[name]) {
    null => null,
    final int value => value,
    _ => throw McpArgumentError('"$name" must be an integer.'),
  };

  /// The list of strings [name], or `null`.
  List<String>? optionalStrings(String name) => switch (values[name]) {
    null => null,
    final List<Object?> list when list.every((item) => item is String) =>
      list.cast<String>(),
    _ => throw McpArgumentError('"$name" must be a list of strings.'),
  };

  /// The object argument [name], or `null`.
  Map<String, Object?>? optionalObject(String name) => switch (values[name]) {
    null => null,
    final Map<String, Object?> map => map,
    _ => throw McpArgumentError('"$name" must be an object.'),
  };
}
