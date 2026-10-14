import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/github_client.dart';
import 'package:xp_engine/src/git/github_exceptions.dart';
import 'package:xp_engine/src/git/github_models.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// Which pull request to open.
class GitHubCreatePrInput extends Equatable {
  /// Creates the input.
  const new({
    required this.githubRepoId,
    required this.head,
    required this.base,
    required this.title,
    this.body,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final repo = json['githubRepoId'];
    if (repo is! int) {
      throw const FormatException('"githubRepoId" must be a number.');
    }
    return GitHubCreatePrInput(
      githubRepoId: repo,
      head: requiredString(json, 'head'),
      base: requiredString(json, 'base'),
      title: requiredString(json, 'title'),
      body: optionalString(json, 'body'),
    );
  }

  /// The GitHub id of the repository, which stays across renames (D-05).
  final int githubRepoId;

  /// The release branch.
  final String head;

  /// The branch it merges into.
  final String base;

  /// The title of the pull request.
  final String title;

  /// Its description.
  final String? body;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'githubRepoId': githubRepoId,
    'head': head,
    'base': base,
    'title': title,
    'body': ?body,
  };

  @override
  List<Object?> get props => [githubRepoId, head, base, title, body];
}

/// The pull request `github.createPr` opened or found.
class GitHubCreatePrResult extends Equatable {
  /// Creates the result.
  const new({
    required this.number,
    required this.url,
    required this.headSha,
    required this.reused,
  });

  /// The number in the repository.
  final int number;

  /// Where to see it.
  final String url;

  /// The commit at the tip of the release branch when it was read.
  final String headSha;

  /// Whether the pull request existed already.
  final bool reused;

  @override
  List<Object?> get props => [number, url, headSha, reused];
}

/// Opens the pull request of a release from its branch into the base branch
/// (`github.createPr`).
///
/// The release branch is pushed by `git.push` first (the push is a gated
/// action, D-13), so the pull request is opened once the build is uploaded and
/// tagged: that is the choice of Phase 12b over opening it when the release
/// starts, when the branch is not on GitHub yet. An open pull request for the
/// same branches is reused, which is also what a new build of the same version
/// finds. Merging it is a separate, gated step (`github.mergePr`).
class GitHubCreatePrStep
    extends Step<GitHubCreatePrInput, GitHubCreatePrResult> {
  /// Creates the step.
  const new(this._github);

  final GitHubClient _github;

  @override
  String get kind => 'github.createPr';

  @override
  bool sideEffectOf(GitHubCreatePrInput input) => true;

  @override
  GitHubCreatePrInput decodeInput(Map<String, dynamic> json) =>
      GitHubCreatePrInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitHubCreatePrInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitHubCreatePrResult result) => {
    'number': result.number,
    'url': result.url,
    'headSha': result.headSha,
    'reused': result.reused,
  };

  /// Done when the pull request is open.
  @override
  Future<GitHubCreatePrResult?> alreadyDone(
    GitHubCreatePrInput input,
    StepContext context,
  ) async {
    final repo = await _github.getRepoById(input.githubRepoId);
    final found = await _github.findPullRequest(
      repo,
      head: input.head,
      base: input.base,
    );
    return found == null ? null : _result(found, reused: true);
  }

  @override
  Future<StepOutcome<GitHubCreatePrResult>> run(
    GitHubCreatePrInput input,
    StepContext context,
  ) async {
    try {
      final found = await alreadyDone(input, context);
      if (found != null) return StepSucceeded(found);
      final repo = await _github.getRepoById(input.githubRepoId);
      final created = await _github.createPullRequest(
        repo,
        title: input.title,
        head: input.head,
        base: input.base,
        body: input.body,
      );
      return StepSucceeded(_result(created, reused: false));
    } on GitHubException catch (error) {
      return StepFailed('GitHub refused the pull request: ${error.message}');
    }
  }

  GitHubCreatePrResult _result(
    GitHubPullRequest pullRequest, {
    required bool reused,
  }) => GitHubCreatePrResult(
    number: pullRequest.number,
    url: pullRequest.htmlUrl,
    headSha: pullRequest.headSha,
    reused: reused,
  );
}
