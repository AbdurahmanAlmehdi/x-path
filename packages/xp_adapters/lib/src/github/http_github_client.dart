import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_engine/xp_engine.dart';

/// A [GitHubClient] over the GitHub REST API.
///
/// Authenticates with the token under `github.token` in the [SecretStore] and
/// sends it only to the host of the base URL. Redirects are followed by hand,
/// for that host only, so that a renamed repository (`301` with a `Location`)
/// resolves to its current name without the token going anywhere else.
class HttpGitHubClient implements GitHubClient {
  /// Creates a client.
  ///
  /// The base URL is `https://api.github.com` unless a test or an Enterprise
  /// server says otherwise. [client] is for tests.
  new({required this._secrets, http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.github.com');

  static const _maxRedirects = 3;
  static const _redirectStatuses = {301, 302, 307, 308};

  final SecretStore _secrets;
  final http.Client _client;
  final Uri _baseUrl;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<GitHubRepo> getRepo(String owner, String name) async {
    final repo = _repo(await _json('GET', ['repos', owner, name]));
    final asked = '$owner/$name';
    if (repo.fullName.toLowerCase() == asked.toLowerCase()) return repo;
    return GitHubRepo(
      id: repo.id,
      fullName: repo.fullName,
      defaultBranch: repo.defaultBranch,
      cloneUrl: repo.cloneUrl,
      renamedFrom: asked,
    );
  }

  @override
  Future<GitHubRepo> getRepoById(int id) async =>
      _repo(await _json('GET', ['repositories', '$id']));

  @override
  Future<GitHubPullRequest> createPullRequest(
    GitHubRepo repo, {
    required String title,
    required String head,
    required String base,
    String? body,
  }) async => _pullRequest(
    await _json(
      'POST',
      _pullsPath(repo),
      body: {'title': title, 'head': head, 'base': base, 'body': ?body},
    ),
  );

  @override
  Future<GitHubPullRequest> getPullRequest(GitHubRepo repo, int number) async =>
      _pullRequest(await _json('GET', _pullsPath(repo, number)));

  @override
  Future<GitHubMergeResult> mergePullRequest(
    GitHubRepo repo,
    int number, {
    GitHubMergeMethod method = GitHubMergeMethod.merge,
    String? expectedHeadSha,
  }) async {
    final json = await _json(
      'PUT',
      [..._pullsPath(repo, number), 'merge'],
      body: {'merge_method': method.apiValue, 'sha': ?expectedHeadSha},
    );
    final message = _string(json, 'message');
    if (json['merged'] != true) throw GitHubNotMergeableException(message);
    return GitHubMergeResult(sha: _string(json, 'sha'), message: message);
  }

  List<String> _pullsPath(GitHubRepo repo, [int? number]) => [
    'repos',
    repo.owner,
    repo.name,
    'pulls',
    if (number != null) '$number',
  ];

  /// Calls the API and decodes the JSON object it answers with.
  Future<Map<String, dynamic>> _json(
    String method,
    List<String> segments, {
    Map<String, Object?>? body,
  }) async {
    final token = await _secrets.read(githubTokenSecretKey);
    if (token == null) {
      throw const GitHubAuthException(
        'There is no GitHub token. Import one with `gh auth login`.',
      );
    }
    var url = _baseUrl.replace(
      pathSegments: [
        ..._baseUrl.pathSegments.where((s) => s.isNotEmpty),
        ...segments,
      ],
    );
    for (var hops = 0; ; hops++) {
      final request = http.Request(method, url)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'User-Agent': 'xpath',
          'X-GitHub-Api-Version': '2022-11-28',
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (_redirectStatuses.contains(response.statusCode)) {
        url = _redirectTarget(url, response, hops);
        continue;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decode(response);
      }
      throw _error(response);
    }
  }

  /// Where a redirect leads, if it is safe to follow it with the token.
  Uri _redirectTarget(Uri from, http.Response response, int hops) {
    final location = response.headers['location'];
    if (location == null || hops >= _maxRedirects) {
      throw GitHubException(
        response.statusCode,
        'GitHub redirected without a usable location.',
      );
    }
    final target = from.resolve(location);
    if (target.scheme != _baseUrl.scheme ||
        target.host != _baseUrl.host ||
        target.port != _baseUrl.port) {
      throw GitHubException(
        response.statusCode,
        'GitHub redirected to another host, ${target.host}.',
      );
    }
    return target;
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on Object {
      throw GitHubException(
        response.statusCode,
        'GitHub answered with something that is not a JSON object.',
      );
    }
  }

  GitHubException _error(http.Response response) {
    final message = _errorMessage(response);
    return switch (response.statusCode) {
      401 => GitHubAuthException(message),
      403 => GitHubForbiddenException(
        message,
        rateLimited:
            response.headers['x-ratelimit-remaining'] == '0' ||
            message.toLowerCase().contains('rate limit'),
      ),
      404 => GitHubNotFoundException(message),
      405 => GitHubNotMergeableException(message),
      409 => GitHubConflictException(message),
      422 => GitHubValidationException(message),
      final status => GitHubException(status, message),
    };
  }

  String _errorMessage(http.Response response) {
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final details = [
        for (final error in json['errors'] as List<dynamic>? ?? const [])
          if (error is Map<String, dynamic> && error['message'] is String)
            error['message'] as String
          else if (error is String)
            error,
      ];
      final message = json['message'] as String? ?? 'GitHub refused.';
      return details.isEmpty ? message : '$message ${details.join('; ')}';
    } on Object {
      return 'GitHub answered ${response.statusCode}.';
    }
  }

  GitHubRepo _repo(Map<String, dynamic> json) => GitHubRepo(
    id: _int(json, 'id'),
    fullName: _string(json, 'full_name'),
    defaultBranch: _string(json, 'default_branch'),
    cloneUrl: _string(json, 'clone_url'),
  );

  GitHubPullRequest _pullRequest(Map<String, dynamic> json) {
    final head = _object(json, 'head');
    final merged = json['merged'] == true;
    return GitHubPullRequest(
      number: _int(json, 'number'),
      title: _string(json, 'title'),
      state: merged
          ? GitHubPullRequestState.merged
          : _string(json, 'state') == 'closed'
          ? GitHubPullRequestState.closed
          : GitHubPullRequestState.open,
      headRef: _string(head, 'ref'),
      headSha: _string(head, 'sha'),
      baseRef: _string(_object(json, 'base'), 'ref'),
      htmlUrl: _string(json, 'html_url'),
      mergeCommitSha: merged ? json['merge_commit_sha'] as String? : null,
    );
  }

  Map<String, dynamic> _object(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is Map<String, dynamic>) return value;
    throw _malformed(key);
  }

  String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw _malformed(key);
  }

  int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw _malformed(key);
  }

  GitHubException _malformed(String key) =>
      GitHubException(0, 'GitHub answered without a usable `$key`.');
}
