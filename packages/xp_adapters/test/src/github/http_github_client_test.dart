import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';

const _token = 'ghp_faketoken';

const _repo = GitHubRepo(
  id: 42,
  fullName: 'acme/app',
  defaultBranch: 'main',
  cloneUrl: 'https://github.com/acme/app.git',
);

Map<String, Object?> _repoJson({String fullName = 'acme/app'}) => {
  'id': 42,
  'full_name': fullName,
  'default_branch': 'main',
  'clone_url': 'https://github.com/$fullName.git',
};

Map<String, Object?> _prJson({
  String state = 'open',
  bool merged = false,
  String? mergeCommit,
}) => {
  'number': 7,
  'title': 'Release 1.0',
  'state': state,
  'merged': merged,
  'html_url': 'https://github.com/acme/app/pull/7',
  'head': {'ref': 'release/1.0', 'sha': 'headsha'},
  'base': {'ref': 'main'},
  'merge_commit_sha': mergeCommit,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late MemorySecretStore secrets;
  late List<http.BaseRequest> requests;
  late List<String> bodies;

  HttpGitHubClient clientAnswering(
    http.Response Function(http.Request request) answer, {
    Uri? baseUrl,
  }) {
    requests = [];
    bodies = [];
    return HttpGitHubClient(
      secrets: secrets,
      baseUrl: baseUrl,
      client: MockClient((request) async {
        requests.add(request);
        bodies.add(request.body);
        return answer(request);
      }),
    );
  }

  setUp(
    () => secrets = MemorySecretStore()..values[githubTokenSecretKey] = _token,
  );

  group('getRepo', () {
    test('reads the repository with the bearer token', () async {
      final client = clientAnswering((_) => _json(_repoJson()));

      final repo = await client.getRepo('acme', 'app');

      expect(repo, _repo);
      expect(repo.renamedFrom, isNull);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.github.com/repos/acme/app');
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Accept'], 'application/vnd.github+json');
      expect(request.headers['User-Agent'], 'xpath');
      expect(request.headers['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('follows the rename redirect and reports the old name', () async {
      final client = clientAnswering((request) {
        if (request.url.path == '/repos/acme/old-name') {
          return http.Response(
            '{"message":"Moved Permanently"}',
            301,
            headers: {'location': 'https://api.github.com/repositories/42'},
          );
        }
        expect(request.url.path, '/repositories/42');
        return _json(_repoJson(fullName: 'acme/new-name'));
      });

      final repo = await client.getRepo('acme', 'old-name');

      expect(repo.id, 42);
      expect(repo.fullName, 'acme/new-name');
      expect(repo.cloneUrl, 'https://github.com/acme/new-name.git');
      expect(repo.renamedFrom, 'acme/old-name');
      expect(requests, hasLength(2));
      expect(requests.last.headers['Authorization'], 'Bearer $_token');
    });

    test('follows a relative redirect', () async {
      final client = clientAnswering((request) {
        if (request.url.path == '/repos/acme/old') {
          return http.Response(
            '',
            307,
            headers: {'location': '/repositories/42'},
          );
        }
        return _json(_repoJson(fullName: 'other/app'));
      });

      final repo = await client.getRepo('acme', 'old');

      expect(repo.fullName, 'other/app');
      expect(repo.renamedFrom, 'acme/old');
    });

    test('is not a rename when only the case differs', () async {
      final client = clientAnswering((_) => _json(_repoJson()));

      final repo = await client.getRepo('Acme', 'App');

      expect(repo.renamedFrom, isNull);
    });

    test('does not send the token to another host', () async {
      final client = clientAnswering(
        (_) => http.Response(
          '',
          301,
          headers: {'location': 'https://evil.example.com/steal'},
        ),
      );

      await expectLater(
        client.getRepo('acme', 'app'),
        throwsA(
          isA<GitHubException>().having(
            (e) => e.message,
            'message',
            contains('evil.example.com'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test('does not follow a redirect to plain http or another port', () async {
      for (final location in [
        'http://api.github.com/repositories/42',
        'https://api.github.com:8443/repositories/42',
      ]) {
        final client = clientAnswering(
          (_) => http.Response('', 301, headers: {'location': location}),
        );

        await expectLater(
          client.getRepo('acme', 'app'),
          throwsA(isA<GitHubException>()),
          reason: location,
        );
        expect(requests, hasLength(1));
      }
    });

    test('gives up on a redirect without a location', () async {
      final client = clientAnswering((_) => http.Response('', 301));

      await expectLater(
        client.getRepo('acme', 'app'),
        throwsA(
          isA<GitHubException>().having((e) => e.statusCode, 'code', 301),
        ),
      );
    });

    test('gives up on a redirect loop', () async {
      final client = clientAnswering(
        (_) => http.Response(
          '',
          301,
          headers: {'location': 'https://api.github.com/repos/acme/app'},
        ),
      );

      await expectLater(
        client.getRepo('acme', 'app'),
        throwsA(isA<GitHubException>()),
      );
      expect(requests, hasLength(4));
    });

    test('needs a token and sends nothing without one', () async {
      secrets.values.clear();
      final client = clientAnswering((_) => _json(_repoJson()));

      await expectLater(
        client.getRepo('acme', 'app'),
        throwsA(isA<GitHubAuthException>()),
      );
      expect(requests, isEmpty);
    });

    test('lets a locked secret store through', () async {
      final client = HttpGitHubClient(
        secrets: _LockedSecretStore(),
        client: MockClient((_) async => _json(_repoJson())),
      );

      await expectLater(
        client.getRepo('acme', 'app'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('rejects answers that are not repositories', () async {
      for (final body in [
        '[]',
        'not json',
        '{"id":"42","full_name":"a/b","default_branch":"m","clone_url":"u"}',
        '{"id":42,"default_branch":"m","clone_url":"u"}',
      ]) {
        final client = clientAnswering((_) => http.Response(body, 200));

        await expectLater(
          client.getRepo('acme', 'app'),
          throwsA(
            isA<GitHubException>().having(
              (e) => e.statusCode,
              'code',
              anyOf(0, 200),
            ),
          ),
          reason: body,
        );
      }
    });

    test('honours a base URL with a path', () async {
      final client = clientAnswering(
        (_) => _json(_repoJson()),
        baseUrl: Uri.parse('http://localhost:9000/api/v3/'),
      );

      await client.getRepo('acme', 'app');

      expect(
        requests.single.url.toString(),
        'http://localhost:9000/api/v3/repos/acme/app',
      );
    });
  });

  test('getRepoById reads /repositories/{id}', () async {
    final client = clientAnswering(
      (_) => _json(_repoJson(fullName: 'acme/renamed')),
    );

    final repo = await client.getRepoById(42);

    expect(requests.single.url.path, '/repositories/42');
    expect(repo.fullName, 'acme/renamed');
    expect(repo.renamedFrom, isNull);
  });

  group('pull requests', () {
    test('createPullRequest posts title, head and base', () async {
      final client = clientAnswering((_) => _json(_prJson(), 201));

      final pr = await client.createPullRequest(
        _repo,
        title: 'Release 1.0',
        head: 'release/1.0',
        base: 'main',
        body: 'Notes',
      );

      expect(pr.number, 7);
      expect(pr.state, GitHubPullRequestState.open);
      expect(pr.headRef, 'release/1.0');
      expect(pr.headSha, 'headsha');
      expect(pr.baseRef, 'main');
      expect(pr.htmlUrl, 'https://github.com/acme/app/pull/7');
      expect(pr.mergeCommitSha, isNull);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/repos/acme/app/pulls');
      expect(
        requests.single.headers['Content-Type'],
        contains('application/json'),
      );
      expect(jsonDecode(bodies.single), {
        'title': 'Release 1.0',
        'head': 'release/1.0',
        'base': 'main',
        'body': 'Notes',
      });
    });

    test('createPullRequest leaves the body out when there is none', () async {
      final client = clientAnswering((_) => _json(_prJson(), 201));

      await client.createPullRequest(_repo, title: 't', head: 'h', base: 'b');

      expect(jsonDecode(bodies.single), {
        'title': 't',
        'head': 'h',
        'base': 'b',
      });
    });

    test('getPullRequest tells open, closed and merged apart', () async {
      final answers = [
        _prJson(),
        _prJson(state: 'closed'),
        _prJson(state: 'closed', merged: true, mergeCommit: 'mergesha'),
      ];
      final client = clientAnswering((_) => _json(answers.removeAt(0)));

      final open = await client.getPullRequest(_repo, 7);
      final closed = await client.getPullRequest(_repo, 7);
      final merged = await client.getPullRequest(_repo, 7);

      expect(open.state, GitHubPullRequestState.open);
      expect(closed.state, GitHubPullRequestState.closed);
      expect(merged.state, GitHubPullRequestState.merged);
      expect(merged.mergeCommitSha, 'mergesha');
      expect(requests.first.url.path, '/repos/acme/app/pulls/7');
    });

    test('getPullRequest rejects an answer without a head', () async {
      final client = clientAnswering(
        (_) => _json({..._prJson(), 'head': 'oops'}),
      );

      await expectLater(
        client.getPullRequest(_repo, 7),
        throwsA(isA<GitHubException>()),
      );
    });

    test('mergePullRequest merges with a merge commit by default', () async {
      final client = clientAnswering(
        (_) => _json({'sha': 'mergesha', 'merged': true, 'message': 'Merged'}),
      );

      final result = await client.mergePullRequest(_repo, 7);

      expect(
        result,
        const GitHubMergeResult(sha: 'mergesha', message: 'Merged'),
      );
      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, '/repos/acme/app/pulls/7/merge');
      expect(jsonDecode(bodies.single), {'merge_method': 'merge'});
    });

    test('mergePullRequest passes the method and the expected head', () async {
      final client = clientAnswering(
        (_) => _json({'sha': 's', 'merged': true, 'message': 'm'}),
      );

      await client.mergePullRequest(
        _repo,
        7,
        method: GitHubMergeMethod.squash,
        expectedHeadSha: 'headsha',
      );

      expect(jsonDecode(bodies.single), {
        'merge_method': 'squash',
        'sha': 'headsha',
      });
    });

    test('mergePullRequest refuses an answer that did not merge', () async {
      final client = clientAnswering(
        (_) => _json({'sha': 's', 'merged': false, 'message': 'Not merged'}),
      );

      await expectLater(
        client.mergePullRequest(_repo, 7),
        throwsA(
          isA<GitHubNotMergeableException>().having(
            (e) => e.message,
            'message',
            'Not merged',
          ),
        ),
      );
    });
  });

  group('errors', () {
    Future<Object?> failWith(http.Response response) async {
      final client = clientAnswering((_) => response);
      try {
        await client.getRepo('acme', 'app');
      } on Object catch (error) {
        return error;
      }
      return null;
    }

    test('401 is GitHubAuthException', () async {
      expect(
        await failWith(_json({'message': 'Bad credentials'}, 401)),
        isA<GitHubAuthException>().having(
          (e) => e.message,
          'message',
          'Bad credentials',
        ),
      );
    });

    test('403 is GitHubForbiddenException, rate limited or not', () async {
      expect(
        await failWith(_json({'message': 'Resource not accessible'}, 403)),
        isA<GitHubForbiddenException>().having(
          (e) => e.rateLimited,
          'rateLimited',
          isFalse,
        ),
      );
      expect(
        await failWith(
          http.Response(
            '{"message":"Forbidden"}',
            403,
            headers: {'x-ratelimit-remaining': '0'},
          ),
        ),
        isA<GitHubForbiddenException>().having(
          (e) => e.rateLimited,
          'rateLimited',
          isTrue,
        ),
      );
      expect(
        await failWith(_json({'message': 'API rate limit exceeded'}, 403)),
        isA<GitHubForbiddenException>().having(
          (e) => e.rateLimited,
          'rateLimited',
          isTrue,
        ),
      );
    });

    test('404, 405, 409 and 422 have their own types', () async {
      expect(
        await failWith(_json({'message': 'Not Found'}, 404)),
        isA<GitHubNotFoundException>(),
      );
      expect(
        await failWith(_json({'message': 'Not mergeable'}, 405)),
        isA<GitHubNotMergeableException>(),
      );
      expect(
        await failWith(_json({'message': 'Head branch was modified'}, 409)),
        isA<GitHubConflictException>(),
      );
      expect(
        await failWith(_json({'message': 'Validation Failed'}, 422)),
        isA<GitHubValidationException>(),
      );
    });

    test('422 lists the validation errors', () async {
      final error = await failWith(
        _json({
          'message': 'Validation Failed',
          'errors': [
            {'message': 'A pull request already exists'},
            'plain error',
            {'code': 'custom'},
            42,
          ],
        }, 422),
      );

      expect(
        error,
        isA<GitHubValidationException>().having(
          (e) => e.message,
          'message',
          'Validation Failed A pull request already exists; plain error',
        ),
      );
    });

    test('another status is a plain GitHubException', () async {
      expect(
        await failWith(_json({'message': 'Server Error'}, 500)),
        isA<GitHubException>()
            .having((e) => e.statusCode, 'code', 500)
            .having((e) => e.message, 'message', 'Server Error'),
      );
    });

    test('an error without JSON still says the status', () async {
      expect(
        await failWith(http.Response('<html>', 502)),
        isA<GitHubException>().having(
          (e) => e.message,
          'message',
          'GitHub answered 502.',
        ),
      );
      expect(
        await failWith(_json({'no': 'message'}, 500)),
        isA<GitHubException>().having(
          (e) => e.message,
          'message',
          'GitHub refused.',
        ),
      );
    });

    test('the token never appears in a message', () async {
      final error = await failWith(_json({'message': 'Bad credentials'}, 401));

      expect('$error', isNot(contains(_token)));
    });
  });

  test('close closes the HTTP client', () {
    var closed = false;
    HttpGitHubClient(
      secrets: secrets,
      client: _ClosingClient(() => closed = true),
    ).close();

    expect(closed, isTrue);
  });

  test('builds its own HTTP client by default', () {
    HttpGitHubClient(secrets: secrets).close();
  });
}

class _LockedSecretStore extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('locked');
}

class _ClosingClient extends http.BaseClient {
  new(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
