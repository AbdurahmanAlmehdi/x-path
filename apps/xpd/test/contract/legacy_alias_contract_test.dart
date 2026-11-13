@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';

import '../helpers/test_engine.dart';

/// The root paths are deprecated aliases of `/api/v1` for bearer clients
/// (ADR 0018): one route of each group answers at the root what it answers
/// under `/api/v1`, checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  const groups = <(String group, String path, int status)>[
    ('system', '/health', 200),
    ('system', '/version', 200),
    ('system', '/status', 200),
    ('system', '/doctor', 200),
    ('projects', '/projects', 200),
    ('credentials', '/credentials', 200),
    ('workflows', '/workflows/schema', 200),
    ('runs', '/runs', 200),
    ('jobs', '/jobs/job_nope', 404),
    ('artifacts', '/artifacts/art_nope', 404),
    ('tests', '/jobs/job_nope/tests', 404),
    ('approvals', '/approvals', 200),
    ('releases', '/releases', 200),
    ('storage', '/storage/retention', 200),
    ('github token', '/github-token', 200),
    ('runners', '/runners', 200),
    ('runners', '/settings/runner-url', 200),
    ('tokens', '/tokens', 200),
    ('people', '/people', 200),
    ('people', '/me', 200),
  ];

  for (final (group, path, status) in groups) {
    test('$group: GET $path at the root is GET /api/v1$path', () async {
      final mounted = await engine.request(path);
      final alias = await engine.request(path, root: true);

      expect(mounted.statusCode, status, reason: mounted.body);
      expect(alias.statusCode, status, reason: alias.body);
      contract.expectResponse(
        method: 'GET',
        path: path,
        statusCode: alias.statusCode,
        contentType: alias.contentType,
        body: alias.body,
      );
      expect(alias.headers['deprecation'], 'true');
      expect(mounted.headers, isNot(contains('deprecation')));
      if (path != '/doctor' && path != '/status') {
        expect(alias.body, mounted.body);
      }
    });
  }
}
