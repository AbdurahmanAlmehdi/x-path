import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// The JSON form of an error, as `--json` prints it on standard error and an
/// MCP tool returns it: `{"code", "message", "hint"}` (UX-05), and the
/// [issues] of a workflow document when there are any. The [hint] is what
/// this client suggests, in its own words; empty when there is none.
Map<String, Object?> errorJson(
  String code,
  String message, [
  String? hint,
  List<WorkflowIssue> issues = const [],
]) => {
  'code': code,
  'message': message,
  'hint': hint ?? '',
  if (issues.isNotEmpty) 'issues': [for (final issue in issues) issue.toJson()],
};

/// The machine-readable code of [error]: the engine's (`not_found`), or
/// `unknown` when its answer was not an error envelope.
String apiCodeOf(ApiException error) => switch (error.code) {
  null => 'unknown',
  final code => ApiError(code: code, message: '').toJson()['code']! as String,
};
