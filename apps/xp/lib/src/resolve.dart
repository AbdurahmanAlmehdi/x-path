import 'package:xp_client/xp_client.dart';

/// A name the user typed matches no project or workflow, or more than one.
class ReferenceException implements Exception {
  /// Creates the exception.
  const new(this.message, {required this.notFound});

  /// What is wrong and what to try.
  final String message;

  /// Whether nothing matched (as opposed to several things).
  final bool notFound;

  @override
  String toString() => message;
}

/// The id of the project called [reference]: an id (`prj_...`), `owner/name`,
/// or just `name` when only one project has it.
Future<String> resolveProject(XpClient client, String reference) async {
  if (reference.startsWith('prj_')) return reference;
  final wanted = reference.toLowerCase();
  final matches = [
    for (final project in await client.listProjects())
      if (project.fullName.toLowerCase() == wanted ||
          project.fullName.split('/').last.toLowerCase() == wanted)
        project,
  ];
  if (matches.length == 1) return matches.single.id;
  if (matches.isEmpty) {
    throw ReferenceException(
      'No project "$reference". See: xp projects list',
      notFound: true,
    );
  }
  throw ReferenceException(
    '"$reference" is more than one project '
    '(${matches.map((p) => p.fullName).join(', ')}). Use owner/name or the id.',
    notFound: false,
  );
}

/// The id of the workflow called [reference] in [projectId]: an id
/// (`wf_...`) or its name.
Future<String> resolveWorkflow(
  XpClient client,
  String projectId,
  String reference,
) async {
  if (reference.startsWith('wf_')) return reference;
  for (final workflow in await client.listWorkflows(projectId)) {
    if (workflow.name == reference) return workflow.id;
  }
  throw ReferenceException(
    'No workflow "$reference" in this project. See: xp workflows list',
    notFound: true,
  );
}
