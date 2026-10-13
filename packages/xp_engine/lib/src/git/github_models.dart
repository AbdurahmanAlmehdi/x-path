import 'package:equatable/equatable.dart';

/// A GitHub repository.
class GitHubRepo extends Equatable {
  /// Creates a repository record.
  const new({
    required this.id,
    required this.fullName,
    required this.defaultBranch,
    required this.cloneUrl,
    this.renamedFrom,
  });

  /// The id that stays the same across renames and transfers. It keys the
  /// mirror (D-05).
  final int id;

  /// `owner/name` as GitHub spells it now.
  final String fullName;

  /// The branch GitHub shows first, for example `main`.
  final String defaultBranch;

  /// The HTTPS URL to clone and push.
  final String cloneUrl;

  /// The `owner/name` that was asked for, when GitHub knows the repository
  /// under another name now. The caller should store [cloneUrl] as the new
  /// remote (D-05). `null` when the name was current.
  final String? renamedFrom;

  /// The owner part of [fullName].
  String get owner => fullName.split('/').first;

  /// The name part of [fullName].
  String get name => fullName.split('/').last;

  @override
  List<Object?> get props => [
    id,
    fullName,
    defaultBranch,
    cloneUrl,
    renamedFrom,
  ];
}

/// Where a pull request stands.
enum GitHubPullRequestState {
  /// Open and not merged.
  open,

  /// Closed without a merge.
  closed,

  /// Merged.
  merged,
}

/// A GitHub pull request.
class GitHubPullRequest extends Equatable {
  /// Creates a pull request record.
  const new({
    required this.number,
    required this.title,
    required this.state,
    required this.headRef,
    required this.headSha,
    required this.baseRef,
    required this.htmlUrl,
    this.mergeCommitSha,
  });

  /// The number in the repository.
  final int number;

  /// The title.
  final String title;

  /// Whether it is open, closed or merged.
  final GitHubPullRequestState state;

  /// The branch it merges from.
  final String headRef;

  /// The commit at the tip of [headRef] when it was read.
  final String headSha;

  /// The branch it merges into.
  final String baseRef;

  /// Where to see it in a browser.
  final String htmlUrl;

  /// The commit the merge created, once merged.
  final String? mergeCommitSha;

  @override
  List<Object?> get props => [
    number,
    title,
    state,
    headRef,
    headSha,
    baseRef,
    htmlUrl,
    mergeCommitSha,
  ];
}

/// How a pull request is merged.
enum GitHubMergeMethod {
  /// A merge commit. The default: it keeps the release commits and their SHAs
  /// intact, so tags made on the branch stay reachable from the base.
  merge('merge'),

  /// All commits squashed into one. Tags on the branch are no longer
  /// reachable from the base.
  squash('squash'),

  /// Commits replayed on the base. New SHAs, so tags on the branch are no
  /// longer reachable from the base.
  rebase('rebase');

  new(this.apiValue);

  /// The value of GitHub's `merge_method` field.
  final String apiValue;
}

/// The outcome of merging a pull request.
class GitHubMergeResult extends Equatable {
  /// Creates a merge result.
  const new({required this.sha, required this.message});

  /// The merge commit.
  final String sha;

  /// What GitHub said, for example `Pull Request successfully merged`.
  final String message;

  @override
  List<Object?> get props => [sha, message];
}
