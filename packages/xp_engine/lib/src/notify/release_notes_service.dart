import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/notify/release_notes_builder.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/releases/release_exceptions.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_model.dart';
import 'package:xp_engine/src/versioning/release_model_repository.dart';

/// The notes of a release (D-22): the commits since the release before it.
///
/// The release before is the newest tag of the same app and flavor that the
/// project's release model reads as a release (not a patch) of a lower
/// version. It reads the engine's mirror as it is and does not fetch: a
/// release is tagged and pushed from the mirror, so the mirror has its
/// commits.
class ReleaseNotesService {
  /// Creates the service.
  ///
  /// A release with no release before it gets its latest [firstReleaseLimit]
  /// commits.
  const new({
    required this._releases,
    required this._projects,
    required this._models,
    required this._git,
    this.builder = const ReleaseNotesBuilder(),
    this.firstReleaseLimit = 100,
  });

  /// How many commits a release with no release before it lists.
  final int firstReleaseLimit;

  /// Writes the notes.
  final ReleaseNotesBuilder builder;

  final ReleaseRepository _releases;
  final ProjectRepository _projects;
  final ReleaseModelRepository _models;
  final GitService _git;

  /// The notes of the release [id].
  ///
  /// Throws a [ReleaseNotFoundException], a [ProjectNotFoundException] and a
  /// [ReleaseStateException] while the release has no commit (it is not
  /// tagged yet).
  Future<ReleaseNotes> forRelease(String id) async {
    final release =
        await _releases.get(id) ?? (throw ReleaseNotFoundException(id));
    final project =
        await _projects.get(release.projectId) ??
        (throw ProjectNotFoundException(release.projectId));
    final mirror = await _git.ensureMirror(
      githubRepoId: project.githubRepoId!,
      remoteUrl: project.remote,
    );
    final to = await _endOf(release.headSha, release.tag, mirror, release.id);
    final model = await _models.get(project.id);
    final appName = project.profile.apps
        .where((app) => app.path == release.appPath)
        .map((app) => app.name)
        .firstOrNull;
    final scope = TagScope(
      app: appName,
      flavor: release.flavor.isEmpty ? null : release.flavor,
    );
    final from = _previousTag(
      await _git.listTags(mirror),
      model,
      scope,
      VersionName.parse(release.version),
    );
    final commits = await _git.commitsBetween(
      mirror,
      from: from,
      to: to,
      limit: from == null ? firstReleaseLimit : 500,
    );
    final flavor = release.flavor.isEmpty ? '' : ' ${release.flavor}';
    return builder.build(
      releaseId: release.id,
      title: '${project.fullName}$flavor ${release.version} (${release.build})',
      version: release.version,
      build: release.build,
      to: to,
      from: from,
      commits: commits,
      compareUrl: from == null
          ? null
          : 'https://github.com/${project.fullName}/compare/'
                '${Uri.encodeComponent(from)}...$to',
    );
  }

  Future<String> _endOf(
    String? headSha,
    String? tag,
    GitMirror mirror,
    String releaseId,
  ) async {
    final ref = headSha ?? tag;
    if (ref == null) {
      throw ReleaseStateException(
        'The release $releaseId has no commit yet, so there are no notes.',
      );
    }
    return await _git.resolveRef(mirror, ref);
  }

  String? _previousTag(
    List<GitTagInfo> tags,
    ReleaseModel model,
    TagScope scope,
    VersionName version,
  ) {
    ReleaseTag? best;
    for (final info in tags) {
      final tag = model.parseTag(info.name, scope: scope);
      if (tag == null || tag.isPatch || version.compareTo(tag.version) <= 0) {
        continue;
      }
      if (best == null ||
          tag.version.compareTo(best.version) > 0 ||
          (tag.version == best.version && tag.build > best.build)) {
        best = tag;
      }
    }
    return best?.name;
  }
}
