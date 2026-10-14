import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/release_helpers.dart';
import '../../../helpers/test_engine.dart';

void main() {
  late ReleaseClient client;

  setUp(() async => client = await ReleaseClient.start());
  tearDown(() => client.close());

  ErrorResponse errorOf(RawResponse response) =>
      ErrorResponse.fromJson(response.json);

  StoreReading reading(StoreState? state, [String detail = 'DETAIL']) =>
      StoreReading(state: state, source: StatusSource.api, detail: detail);

  group('GET /releases', () {
    test('lists the releases, newest first', () async {
      final first = await client.open();
      client.engine.clock.advance(const Duration(minutes: 1));
      final second = await client.open(
        version: '1.3.0',
        build: 6,
        runId: 'run_2',
      );

      final response = await client.send('GET', '/releases');

      expect(response.statusCode, 200);
      final listed = ReleasesResponse.fromJson(response.json).releases;
      expect([for (final r in listed) r.id], [second, first]);
      expect(listed.last.state, ReleaseState.draft);
      expect(listed.last.version, '1.2.0');
      expect(listed.last.build, 5);
      expect(listed.last.projectId, client.projectId);
      expect(listed.last.flavor, 'default');
      expect(listed.last.stores.map((s) => s.store), [
        ReleaseStore.apple,
        ReleaseStore.play,
      ]);
    });

    test('is empty for an engine with no release', () async {
      final response = await client.send('GET', '/releases');

      expect(response.json, {'releases': <Object?>[]});
    });

    test('filters by project, app and state', () async {
      final live = await client.uploaded();
      final draft = await client.open(runId: 'run_2', version: '2.0.0');
      await client.send(
        'POST',
        '/releases/$live/stores/apple/status',
        body: {'state': 'live'},
      );

      List<String> ids(RawResponse response) => [
        for (final r in ReleasesResponse.fromJson(response.json).releases) r.id,
      ];
      expect(ids(await client.send('GET', '/releases?state=draft')), [draft]);
      expect(
        ids(
          await client.send(
            'GET',
            '/releases?project=${client.projectId}&app=.',
          ),
        ),
        [draft, live],
      );
      expect(
        ids(await client.send('GET', '/releases?project=prj_other')),
        isEmpty,
      );
      expect(
        ids(await client.send('GET', '/releases?app=packages/x')),
        isEmpty,
      );
    });

    test('answers 400 for a state it does not know', () async {
      final response = await client.send('GET', '/releases?state=flying');

      expect(response.statusCode, 400);
      expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      expect(errorOf(response).error.message, contains('in_review'));
    });

    test('needs a token', () async {
      final response = await client.engine.request('/releases', token: '');

      expect(response.statusCode, 401);
    });
  });

  group('GET /releases/{id}', () {
    test('shows the release brought up to date with its jobs', () async {
      final id = await client.open();
      await client.finishBuild(id);

      final response = await client.send('GET', '/releases/$id');

      expect(response.statusCode, 200);
      final release = Release.fromJson(response.json);
      expect(release.state, ReleaseState.uploaded);
      expect(release.branch, 'release/1.2.0');
      expect(release.tag, 'v1.2.0+5');
      expect(release.prNumber, 7);
      expect(release.mergeEnabled, isFalse);
    });

    test('is readable by every kind of token', () async {
      final id = await client.open();

      for (final kind in DeviceTokenKind.values) {
        final response = await client.send('GET', '/releases/$id', kind: kind);

        expect(response.statusCode, 200, reason: kind.name);
      }
    });

    test('answers 404 for a release that does not exist', () async {
      final response = await client.send('GET', '/releases/rel_nope');

      expect(response.statusCode, 404);
      expect(errorOf(response).error.code, ApiErrorCode.notFound);
    });
  });

  group('POST /releases/{id}/refresh', () {
    test('asks the stores now and moves the release', () async {
      final id = await client.uploaded();
      client.engine.appleStatus.reading = reading(
        StoreState.inReview,
        'IN_REVIEW',
      );
      client.engine.playStatus.reading = reading(StoreState.inReview);

      final response = await client.send('POST', '/releases/$id/refresh');

      expect(response.statusCode, 200);
      final release = Release.fromJson(response.json);
      expect(release.state, ReleaseState.inReview);
      expect(release.stores.first.detail, 'IN_REVIEW');
      expect(
        (await client.logged()).whereType<ReleaseStateChanged>().last.to,
        ReleaseState.inReview,
      );
    });

    test('asks again whatever was asked a minute ago', () async {
      final id = await client.uploaded();
      client.engine.appleStatus.reading = reading(null);
      client.engine.playStatus.reading = reading(null);

      await client.send('POST', '/releases/$id/refresh');
      await client.send(
        'POST',
        '/releases/$id/refresh',
        kind: DeviceTokenKind.mcp,
      );

      expect(client.engine.appleStatus.reads, hasLength(2));
    });

    test('answers 404 for a release that does not exist', () async {
      final response = await client.send('POST', '/releases/rel_nope/refresh');

      expect(response.statusCode, 404);
    });
  });

  group('POST /releases/{id}/stores/{store}/status', () {
    late String id;

    setUp(() async => id = await client.uploaded());

    Future<RawResponse> mark(
      String store,
      Object? body, {
      DeviceTokenKind kind = DeviceTokenKind.app,
    }) => client.send(
      'POST',
      '/releases/$id/stores/$store/status',
      body: body,
      kind: kind,
    );

    test('takes the owner at their word, for app and cli tokens', () async {
      final approved = await mark('apple', {'state': 'approved'});
      final live = await mark('play', {
        'state': 'live',
      }, kind: DeviceTokenKind.cli);

      expect(approved.statusCode, 200);
      expect(live.statusCode, 200);
      final release = Release.fromJson(live.json);
      expect(release.state, ReleaseState.approved);
      expect(release.stores.map((s) => (s.state, s.source)), [
        (StoreState.approved, StatusSource.manual),
        (StoreState.live, StatusSource.manual),
      ]);
    });

    test('is not for an agent or a runner (403)', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await mark('play', {'state': 'live'}, kind: kind);

        expect(response.statusCode, 403, reason: kind.name);
        expect(errorOf(response).error.code, ApiErrorCode.forbidden);
      }
      expect((await client.read(id)).state, ReleaseState.uploaded);
    });

    test(
      'answers 400 for a store, a body or a status it does not take',
      () async {
        final unknownStore = await mark('steam', {'state': 'live'});
        final noBody = await client.send(
          'POST',
          '/releases/$id/stores/apple/status',
        );
        final badState = await mark('apple', {'state': 'soon'});
        final notJson = await client.send(
          'POST',
          '/releases/$id/stores/apple/status',
          rawBody: 'nope',
        );
        final notAllowed = await mark('play', {'state': 'approved'});

        for (final response in [
          unknownStore,
          noBody,
          badState,
          notJson,
          notAllowed,
        ]) {
          expect(response.statusCode, 400, reason: response.body);
          expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
        }
      },
    );

    test('answers 409 once the store is past that status', () async {
      await mark('play', {'state': 'live'});

      final response = await mark('play', {'state': 'live'});

      expect(response.statusCode, 409);
      expect(errorOf(response).error.code, ApiErrorCode.conflict);
    });

    test('answers 404 for a release that does not exist', () async {
      final response = await client.send(
        'POST',
        '/releases/rel_nope/stores/apple/status',
        body: {'state': 'live'},
      );

      expect(response.statusCode, 404);
    });
  });

  group('POST /releases/{id}/builds', () {
    late String id;

    Future<void> reject() async {
      id = await client.uploaded();
      client.engine.appleStatus.reading = reading(
        StoreState.rejected,
        'REJECTED',
      );
      client.engine.playStatus.reading = reading(StoreState.inReview);
      await client.send('POST', '/releases/$id/refresh');
    }

    test('builds the same version again, with a new number', () async {
      await reject();

      final response = await client.send('POST', '/releases/$id/builds');

      expect(response.statusCode, 202, reason: response.body);
      final run = Run.fromJson(response.json);
      expect(response.headers['location'], '/runs/${run.id}');
      expect(run.version, '1.2.0');
      expect(run.build, 1, reason: 'the counter of the app starts at 1');
      expect(run.ref, 'release/1.2.0');
      final release = await client.read(id);
      expect(release.state, ReleaseState.building);
      expect(release.build, 1);
      expect(release.builds.map((b) => b.runId), ['run_1', run.id]);
    });

    test('is for a rejected release only (409)', () async {
      final fresh = await client.open();

      final response = await client.send('POST', '/releases/$fresh/builds');

      expect(response.statusCode, 409);
      expect(errorOf(response).error.code, ApiErrorCode.conflict);
    });

    test('answers 404 for a release that does not exist', () async {
      final response = await client.send('POST', '/releases/rel_nope/builds');

      expect(response.statusCode, 404);
    });
  });

  group('POST /releases/{id}/merge', () {
    late String id;

    Future<void> live() async {
      id = await client.uploaded();
      for (final store in ['apple', 'play']) {
        await client.send(
          'POST',
          '/releases/$id/stores/$store/status',
          body: {'state': 'live'},
        );
      }
    }

    test('requests the merge, which waits for the owner', () async {
      await live();
      expect((await client.read(id)).mergeEnabled, isTrue);

      final response = await client.send(
        'POST',
        '/releases/$id/merge',
        kind: DeviceTokenKind.mcp,
      );

      expect(response.statusCode, 202);
      final run = Run.fromJson(response.json);
      expect(response.headers['location'], '/runs/${run.id}');
      final approvals = await client.engine.approvals.list();
      expect(approvals.single.action, 'merge');
      expect(approvals.single.version, '1.2.0+5');
      expect(approvals.single.sha, 'a' * 40);
      final release = await client.read(id);
      expect(release.mergeEnabled, isFalse);
      expect(release.mergeRunId, run.id);
    });

    test('asked again, answers with the same run', () async {
      await live();
      final first = Run.fromJson(
        (await client.send('POST', '/releases/$id/merge')).json,
      );

      final second = Run.fromJson(
        (await client.send('POST', '/releases/$id/merge')).json,
      );

      expect(second.id, first.id);
    });

    test('waits until every store is live (409)', () async {
      id = await client.uploaded();

      final response = await client.send('POST', '/releases/$id/merge');

      expect(response.statusCode, 409);
      expect(errorOf(response).error.message, contains('uploaded'));
    });

    test('answers 404 for a release that does not exist', () async {
      final response = await client.send('POST', '/releases/rel_nope/merge');

      expect(response.statusCode, 404);
    });
  });

  group('POST /releases/{id}/abandon', () {
    test('gives the release up, with a reason', () async {
      final id = await client.open();

      final response = await client.send(
        'POST',
        '/releases/$id/abandon',
        body: {'reason': 'wrong build'},
      );

      expect(response.statusCode, 200);
      final release = Release.fromJson(response.json);
      expect(release.state, ReleaseState.abandoned);
      expect(release.message, 'wrong build');
    });

    test('needs no body', () async {
      final id = await client.open();

      final response = await client.send(
        'POST',
        '/releases/$id/abandon',
        kind: DeviceTokenKind.cli,
      );

      expect(Release.fromJson(response.json).message, 'Abandoned.');
    });

    test('is not for an agent or a runner (403)', () async {
      final id = await client.open();

      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await client.send(
          'POST',
          '/releases/$id/abandon',
          kind: kind,
        );

        expect(response.statusCode, 403, reason: kind.name);
      }
      expect((await client.read(id)).state, ReleaseState.draft);
    });

    test('answers 400 for a reason that is not text, 404 and 409', () async {
      final id = await client.open();

      final bad = await client.send(
        'POST',
        '/releases/$id/abandon',
        body: {'reason': 5},
      );
      final missing = await client.send('POST', '/releases/rel_nope/abandon');
      await client.send('POST', '/releases/$id/abandon');
      final again = await client.send('POST', '/releases/$id/abandon');

      expect(bad.statusCode, 400);
      expect(missing.statusCode, 404);
      expect(again.statusCode, 409);
    });
  });
}
