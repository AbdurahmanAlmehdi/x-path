import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/projects/apply_edits.dart';

/// What the engine stores about a project: the raw result of the last scan,
/// kept apart from the owner's edits so that a rescan never loses an edit.
class ProjectRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.host,
    required this.sourceKey,
    required this.fullName,
    required this.remote,
    required this.githubDefaultBranch,
    required this.scan,
    required this.findings,
    required this.scannedAt,
    this.githubRepoId,
    this.localPath,
    this.edits = const ProfileEdits(),
  });

  /// The engine's id.
  final String id;

  /// Where the repository lives: `github.com`, another SSH host, or `local`
  /// for a `file://` origin (ADR 0015).
  final String host;

  /// What keys the project's mirror, the runner cache and its worktrees: the
  /// GitHub repository id in decimal, or `h` and 16 hex digits of the
  /// SHA-256 of the normalised remote (ADR 0015).
  final String sourceKey;

  /// The GitHub repository id (D-05), for a project on GitHub only.
  final int? githubRepoId;

  /// `owner/name`: as GitHub spells it now, or the path of the remote.
  final String fullName;

  /// The URL the mirror fetches from.
  final String remote;

  /// The branch the origin shows first.
  final String githubDefaultBranch;

  /// The folder the project was added from, if it was added by path.
  final String? localPath;

  /// What the last scan found, before edits.
  final ProjectProfile scan;

  /// What the last scan noticed.
  final List<Finding> findings;

  /// When the last scan ran.
  final DateTime scannedAt;

  /// The owner's corrections, applied on top of every scan.
  final ProfileEdits edits;

  /// Whether the repository is on GitHub, so GitHub steps can run for it.
  bool get isOnGitHub => host == Project.githubHost;

  /// The branch releases are based on: the owner's choice, else the origin's
  /// default branch.
  String get defaultBaseBranch =>
      edits.defaultBaseBranch ?? githubDefaultBranch;

  /// The scanned profile with the edits applied.
  ProjectProfile get profile => applyEdits(scan, edits);

  /// This record with the given fields replaced.
  ProjectRecord copyWith({
    String? fullName,
    String? remote,
    String? githubDefaultBranch,
    ProjectProfile? scan,
    List<Finding>? findings,
    DateTime? scannedAt,
    ProfileEdits? edits,
  }) => ProjectRecord(
    id: id,
    host: host,
    sourceKey: sourceKey,
    githubRepoId: githubRepoId,
    fullName: fullName ?? this.fullName,
    remote: remote ?? this.remote,
    githubDefaultBranch: githubDefaultBranch ?? this.githubDefaultBranch,
    localPath: localPath,
    scan: scan ?? this.scan,
    findings: findings ?? this.findings,
    scannedAt: scannedAt ?? this.scannedAt,
    edits: edits ?? this.edits,
  );

  /// The API view of the project.
  Project toProject() => Project(
    id: id,
    host: host,
    sourceKey: sourceKey,
    githubRepoId: githubRepoId,
    fullName: fullName,
    remote: remote,
    localPath: localPath,
    defaultBaseBranch: defaultBaseBranch,
    profile: profile,
    findings: findings,
    scannedAt: scannedAt,
  );

  @override
  List<Object?> get props => [
    id,
    host,
    sourceKey,
    githubRepoId,
    fullName,
    remote,
    githubDefaultBranch,
    localPath,
    scan,
    findings,
    scannedAt,
    edits,
  ];
}
