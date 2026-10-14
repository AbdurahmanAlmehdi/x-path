@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/release_helpers.dart';
import '../helpers/test_engine.dart';

/// Every response of the release endpoints is checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late ReleaseClient client;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => client = await ReleaseClient.start());
  tearDown(() => client.close());

  void expectContract(
    RawResponse response, {
    required String path,
    required int status,
    String method = 'GET',
  }) {
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path.split('?').first,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  StoreReading reading(StoreState state) =>
      StoreReading(state: state, source: StatusSource.api, detail: 'X');

  test('request bodies match their schemas', () {
    for (final (schema, body) in <(String, Object)>[
      ('StoreStatusRequest', {'state': 'approved'}),
      ('StoreStatusRequest', {'state': 'live'}),
      ('AbandonRequest', <String, Object>{}),
      ('AbandonRequest', {'reason': 'wrong build'}),
    ]) {
      expect(contract.validateSchema(schema, body), isEmpty, reason: schema);
    }
    expect(
      contract.validateSchema('StoreStatusRequest', {'state': 'rejected'}),
      isNotEmpty,
    );
    expect(
      contract.validateSchema('AbandonRequest', {'reason': 1}),
      isNotEmpty,
    );
  });

  group('releases', () {
    test('GET list 200, 400 and 401', () async {
      await client.open();

      expectContract(
        await client.send('GET', '/releases'),
        path: '/releases',
        status: 200,
      );
      expectContract(
        await client.send(
          'GET',
          '/releases?project=${client.projectId}&app=.&state=draft',
        ),
        path: '/releases',
        status: 200,
      );
      expectContract(
        await client.send('GET', '/releases?state=flying'),
        path: '/releases',
        status: 400,
      );
      expectContract(
        await client.engine.request('/releases', token: ''),
        path: '/releases',
        status: 401,
      );
    });

    test('GET one 200, 401 and 404', () async {
      final id = await client.open();

      expectContract(
        await client.send('GET', '/releases/$id'),
        path: '/releases/$id',
        status: 200,
      );
      expectContract(
        await client.engine.request('/releases/$id', token: ''),
        path: '/releases/$id',
        status: 401,
      );
      expectContract(
        await client.send('GET', '/releases/rel_nope'),
        path: '/releases/rel_nope',
        status: 404,
      );
    });

    test('GET one in every state', () async {
      final states = <ReleaseState, String>{};
      states[ReleaseState.draft] = await client.open();
      final abandoned = await client.open(runId: 'run_2', version: '2.0.0');
      await client.send('POST', '/releases/$abandoned/abandon');
      states[ReleaseState.abandoned] = abandoned;
      final uploaded = await client.open(runId: 'run_3', version: '3.0.0');
      await client.finishBuild(uploaded, runId: 'run_3');
      states[ReleaseState.uploaded] = uploaded;
      final rejected = await client.open(runId: 'run_4', version: '4.0.0');
      await client.finishBuild(rejected, runId: 'run_4');
      client.engine.appleStatus.reading = reading(StoreState.rejected);
      client.engine.playStatus.reading = reading(StoreState.inReview);
      await client.send('POST', '/releases/$rejected/refresh');
      states[ReleaseState.rejected] = rejected;

      for (final MapEntry(key: state, value: id) in states.entries) {
        final response = await client.send('GET', '/releases/$id');

        expectContract(response, path: '/releases/$id', status: 200);
        expect(Release.fromJson(response.json).state, state);
      }
    });

    test('POST refresh 200, 401 and 404', () async {
      final id = await client.uploaded();
      client.engine.appleStatus.reading = reading(StoreState.inReview);
      client.engine.playStatus.reading = reading(StoreState.inReview);

      expectContract(
        await client.send('POST', '/releases/$id/refresh'),
        path: '/releases/$id/refresh',
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.engine.request(
          '/releases/$id/refresh',
          method: 'POST',
          token: '',
        ),
        path: '/releases/$id/refresh',
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send('POST', '/releases/rel_nope/refresh'),
        path: '/releases/rel_nope/refresh',
        method: 'POST',
        status: 404,
      );
    });

    test('POST store status 200, 400, 401, 403, 404 and 409', () async {
      final id = await client.uploaded();
      final path = '/releases/$id/stores/play/status';

      expectContract(
        await client.send('POST', path, body: {'state': 'live'}),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path, rawBody: '{"state": 5}'),
        path: path,
        method: 'POST',
        status: 400,
      );
      expectContract(
        await client.engine.request(path, method: 'POST', token: ''),
        path: path,
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send(
          'POST',
          path,
          body: {'state': 'live'},
          kind: DeviceTokenKind.mcp,
        ),
        path: path,
        method: 'POST',
        status: 403,
      );
      expectContract(
        await client.send(
          'POST',
          '/releases/rel_nope/stores/play/status',
          body: {'state': 'live'},
        ),
        path: '/releases/rel_nope/stores/play/status',
        method: 'POST',
        status: 404,
      );
      expectContract(
        await client.send('POST', path, body: {'state': 'live'}),
        path: path,
        method: 'POST',
        status: 409,
      );
    });

    test('POST builds 202, 401, 404 and 409', () async {
      final fresh = await client.open();
      final rejected = await client.open(runId: 'run_2', version: '2.0.0');
      await client.finishBuild(rejected, runId: 'run_2');
      client.engine.appleStatus.reading = reading(StoreState.rejected);
      client.engine.playStatus.reading = reading(StoreState.inReview);
      await client.send('POST', '/releases/$rejected/refresh');

      expectContract(
        await client.send('POST', '/releases/$rejected/builds'),
        path: '/releases/$rejected/builds',
        method: 'POST',
        status: 202,
      );
      expectContract(
        await client.engine.request(
          '/releases/$fresh/builds',
          method: 'POST',
          token: '',
        ),
        path: '/releases/$fresh/builds',
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send('POST', '/releases/rel_nope/builds'),
        path: '/releases/rel_nope/builds',
        method: 'POST',
        status: 404,
      );
      expectContract(
        await client.send('POST', '/releases/$fresh/builds'),
        path: '/releases/$fresh/builds',
        method: 'POST',
        status: 409,
      );
    });

    test('POST merge 202, 401, 404 and 409', () async {
      final id = await client.uploaded();
      final path = '/releases/$id/merge';

      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 409,
      );
      for (final store in ['apple', 'play']) {
        await client.send(
          'POST',
          '/releases/$id/stores/$store/status',
          body: {'state': 'live'},
        );
      }
      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 202,
      );
      expectContract(
        await client.engine.request(path, method: 'POST', token: ''),
        path: path,
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send('POST', '/releases/rel_nope/merge'),
        path: '/releases/rel_nope/merge',
        method: 'POST',
        status: 404,
      );
    });

    test('POST abandon 200, 400, 401, 403, 404 and 409', () async {
      final id = await client.open();
      final path = '/releases/$id/abandon';

      expectContract(
        await client.send('POST', path, rawBody: '{"reason": 5}'),
        path: path,
        method: 'POST',
        status: 400,
      );
      expectContract(
        await client.engine.request(path, method: 'POST', token: ''),
        path: path,
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send('POST', path, kind: DeviceTokenKind.mcp),
        path: path,
        method: 'POST',
        status: 403,
      );
      expectContract(
        await client.send('POST', '/releases/rel_nope/abandon'),
        path: '/releases/rel_nope/abandon',
        method: 'POST',
        status: 404,
      );
      expectContract(
        await client.send('POST', path, body: {'reason': 'wrong'}),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 409,
      );
    });
  });
}
