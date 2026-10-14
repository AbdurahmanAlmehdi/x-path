import 'package:xp/src/commands/runs_commands.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp releases`: releases from draft to merged (D-17).
XpGroup releasesCommand(XpContext context) => XpGroup(
  context,
  'releases',
  'List and show releases, refresh them, and drive them by hand.',
  [
    ReleasesListCommand(context),
    ReleasesShowCommand(context),
    ReleasesRefreshCommand(context),
    ReleasesStatusCommand(context),
    ReleasesBuildCommand(context),
    ReleasesMergeCommand(context),
    ReleasesAbandonCommand(context),
    ReleasesNotesCommand(context),
  ],
);

/// The lines `xp releases show` prints.
String describeRelease(Release release) {
  final head =
      '${release.id}  ${release.state.wire}  '
      '${release.version}+${release.build}  ${release.flavor}';
  final pullRequest =
      'pull request: ${release.prUrl}  merge enabled: '
      '${release.mergeEnabled ? 'yes' : 'no'}';
  return [
    head,
    'project: ${release.projectId}  app: ${release.app}',
    if (release.branch != null) 'branch: ${release.branch}',
    if (release.tag != null) 'tag: ${release.tag}',
    if (release.prUrl != null) pullRequest,
    if (release.message != null) 'message: ${release.message}',
    '',
    renderTable(
      ['STORE', 'STATE', 'SOURCE', 'CHECKED'],
      [
        for (final store in release.stores)
          [
            store.store.wire,
            store.state.wire,
            store.source.wire,
            formatTime(store.checkedAt),
          ],
      ],
    ),
  ].join('\n');
}

/// `xp releases list`.
class ReleasesListCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption('project', help: 'Only the releases of this project.')
      ..addOption('app', help: 'Only the releases of this app path.')
      ..addOption(
        'state',
        help: 'Only the releases in this state.',
        allowed: ReleaseState.values.map((state) => state.wire),
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List the releases, newest first.';

  @override
  Future<int> execute(XpClient client) async {
    final projectReference = argResults!.option('project');
    final state = argResults!.option('state');
    final releases = await client.listReleases(
      projectId: projectReference == null
          ? null
          : await resolveProject(client, projectReference),
      app: argResults!.option('app'),
      state: state == null
          ? null
          : ReleaseState.values.firstWhere((value) => value.wire == state),
    );
    emit([for (final release in releases) release.toJson()], () {
      if (releases.isEmpty) return 'No releases.';
      return renderTable(
        ['ID', 'STATE', 'VERSION', 'FLAVOR', 'UPDATED'],
        [
          for (final release in releases)
            [
              release.id,
              release.state.wire,
              '${release.version}+${release.build}',
              release.flavor,
              formatTime(release.updatedAt),
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// A command that takes a release and prints the release it gets back.
abstract class _ReleaseCommand extends XpCommand {
  new(super.context);

  Future<Release> act(XpClient client, String id);

  @override
  String get invocation => 'xp releases $name <release>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['release']);
    final release = await act(client, id);
    emit(release.toJson(), () => describeRelease(release));
    return XpExit.ok;
  }
}

/// `xp releases show <release>`.
class ReleasesShowCommand extends _ReleaseCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description => 'Show a release and the state in each store.';

  @override
  Future<Release> act(XpClient client, String id) => client.getRelease(id);
}

/// `xp releases refresh <release>`.
class ReleasesRefreshCommand extends _ReleaseCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'refresh';

  @override
  String get description => 'Ask the stores about the release now.';

  @override
  Future<Release> act(XpClient client, String id) => client.refreshRelease(id);
}

/// `xp releases status <release> <apple|play> <state>`.
class ReleasesStatusCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'status';

  @override
  String get description =>
      'Say by hand what a store did (when it has no API for it).';

  @override
  String get invocation => 'xp releases status <release> <apple|play> <state>';

  @override
  Future<int> execute(XpClient client) async {
    final [id, storeName, stateName] = positionals([
      'release',
      'store',
      'state',
    ]);
    final store = ReleaseStore.values.where((s) => s.wire == storeName);
    if (store.isEmpty) {
      usageException(
        'The store is ${ReleaseStore.values.map((s) => s.wire).join(' or ')}.',
      );
    }
    final state = StoreState.values.where((s) => s.wire == stateName);
    if (state.isEmpty) {
      usageException(
        'The state is one of '
        '${StoreState.values.map((s) => s.wire).join(', ')}.',
      );
    }
    final release = await client.setReleaseStoreStatus(
      id,
      store.single,
      state.single,
    );
    emit(release.toJson(), () => describeRelease(release));
    return XpExit.ok;
  }
}

/// `xp releases build <release>`.
class ReleasesBuildCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build the same version again with a new build number.';

  @override
  String get invocation => 'xp releases build <release>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['release']);
    final run = await client.startReleaseBuild(id);
    emit(run.toJson(), () => 'Started ${run.id}.\n\n${describeRun(run)}');
    return XpExit.ok;
  }
}

/// `xp releases merge <release>`.
class ReleasesMergeCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'merge';

  @override
  String get description =>
      'Merge the release pull request (waits for the merge approval).';

  @override
  String get invocation => 'xp releases merge <release>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['release']);
    final run = await client.mergeRelease(id);
    emit(run.toJson(), () => 'Started ${run.id}.\n\n${describeRun(run)}');
    return XpExit.ok;
  }
}

/// `xp releases abandon <release>`.
class ReleasesAbandonCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption('reason', help: 'Why, for the record.');
  }

  @override
  String get name => 'abandon';

  @override
  String get description => 'Give a release up.';

  @override
  String get invocation => 'xp releases abandon <release> [--reason <text>]';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['release']);
    final release = await client.abandonRelease(
      id,
      reason: argResults!.option('reason'),
    );
    emit(release.toJson(), () => describeRelease(release));
    return XpExit.ok;
  }
}

/// `xp releases notes <release>`.
class ReleasesNotesCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'format',
      help: 'The text to print.',
      allowed: ['slack', 'whatsapp'],
      defaultsTo: 'slack',
    );
  }

  @override
  String get name => 'notes';

  @override
  String get description => 'Print the release notes, ready to paste.';

  @override
  String get invocation =>
      'xp releases notes <release> [--format slack|whatsapp]';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['release']);
    final notes = await client.getReleaseNotes(id);
    emit(
      notes.toJson(),
      () => argResults!.option('format') == 'whatsapp'
          ? notes.whatsapp
          : notes.slack,
    );
    return XpExit.ok;
  }
}
