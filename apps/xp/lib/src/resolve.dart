import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// A name the user typed matches no project, workflow or runner, or more than
/// one.
class ReferenceException implements Exception {
  /// Creates the exception.
  const new(this.message, {required this.notFound, this.listing});

  /// What is wrong, in words every client can show.
  final String message;

  /// Whether nothing matched (as opposed to several things).
  final bool notFound;

  /// What lists the names that would match (`projects`, `workflows`,
  /// `credentials`); each client names its own way to list them.
  final String? listing;

  /// What the CLI suggests: the command that lists the names.
  String? get cliHint => listing == null ? null : 'See: xp $listing list';

  /// What MCP suggests: the tool that lists the names.
  String? get mcpHint => listing == null ? null : 'See: list_$listing';

  @override
  String toString() => [message, ?cliHint].join(' ');
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
      'No project "$reference".',
      notFound: true,
      listing: 'projects',
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
    'No workflow "$reference" in this project.',
    notFound: true,
    listing: 'workflows',
  );
}

/// The id of the runner called [reference]: an id (`rnr_...`) or its name.
Future<String> resolveRunner(XpClient client, String reference) async {
  if (reference.startsWith('rnr_')) return reference;
  for (final runner in await client.listRunners()) {
    if (runner.name == reference) return runner.id;
  }
  throw ReferenceException(
    'No runner "$reference". Give the name it was paired with, or its id.',
    notFound: true,
  );
}

/// The named credential called [reference]: the id (`crd_...`) of one, or
/// its name regardless of case.
Future<NamedCredential> resolveCredential(
  XpClient client,
  String reference,
) async {
  final credentials = await client.listNamedCredentials();
  if (reference.startsWith('crd_')) {
    for (final credential in credentials) {
      if (credential.id == reference) return credential;
    }
  }
  final wanted = reference.toLowerCase();
  for (final credential in credentials) {
    if (credential.name.toLowerCase() == wanted) return credential;
  }
  throw ReferenceException(
    'No credential "$reference".',
    notFound: true,
    listing: 'credentials',
  );
}
