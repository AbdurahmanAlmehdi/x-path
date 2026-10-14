@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/test_engine.dart';

/// Every response of the storage endpoints is checked against `openapi.yaml`,
/// and so are the notification events the app receives.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late String mcp;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    mcp = (await engine.tokens.issue(
      name: 'agent',
      kind: DeviceTokenKind.mcp,
    )).secret;
  });
  tearDown(() => engine.close());

  void expectContract(
    RawResponse response, {
    required String path,
    required int status,
    String method = 'GET',
  }) {
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  Future<RawResponse> send(
    String method,
    String path, {
    String? token,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: token,
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  test('request bodies match their schemas', () {
    for (final (schema, body) in <(String, Object)>[
      ('FreeSpaceRequest', <String, Object>{}),
      ('FreeSpaceRequest', {'dryRun': false}),
      (
        'FreeSpaceRequest',
        {
          'dryRun': true,
          'categories': [
            'artifacts',
            'logs',
            'worktrees',
            'mirrors',
            'flutter',
          ],
        },
      ),
      ('RetentionSettings', {'keepPerFlavor': 3, 'logDays': 30}),
    ]) {
      expect(contract.validateSchema(schema, body), isEmpty, reason: schema);
    }
    expect(
      contract.validateSchema('RetentionSettings', {'logDays': 0}),
      isNotEmpty,
    );
  });

  test('GET /storage 200 and 401', () async {
    expectContract(
      await send('GET', '/storage'),
      path: '/storage',
      status: 200,
    );
    for (var day = 1; day <= 7; day++) {
      await engine.jobRepository.create(
        JobRecord(
          id: 'job_$day',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.succeeded,
          createdAt: engine.clock.now().subtract(Duration(days: day)),
        ),
        const [],
      );
      await engine.addArtifact('job_$day');
    }
    expectContract(
      await send('GET', '/storage'),
      path: '/storage',
      status: 200,
    );
    expectContract(
      await send('GET', '/storage', token: ''),
      path: '/storage',
      status: 401,
    );
  });

  test('POST /storage/free 200, 400, 401 and 403', () async {
    const path = '/storage/free';

    expectContract(
      await send('POST', path),
      path: path,
      method: 'POST',
      status: 200,
    );
    expectContract(
      await send('POST', path, body: {'dryRun': false}),
      path: path,
      method: 'POST',
      status: 200,
    );
    expectContract(
      await send('POST', path, rawBody: '{"categories": ["unicorns"]}'),
      path: path,
      method: 'POST',
      status: 400,
    );
    expectContract(
      await send('POST', path, token: ''),
      path: path,
      method: 'POST',
      status: 401,
    );
    expectContract(
      await send('POST', path, token: mcp, body: {'dryRun': false}),
      path: path,
      method: 'POST',
      status: 403,
    );
  });

  test('GET and PUT /storage/retention 200, 400, 401 and 403', () async {
    const path = '/storage/retention';

    expectContract(await send('GET', path), path: path, status: 200);
    expectContract(await send('GET', path, token: ''), path: path, status: 401);
    expectContract(
      await send('PUT', path, body: {'keepPerFlavor': 3}),
      path: path,
      method: 'PUT',
      status: 200,
    );
    expectContract(
      await send('PUT', path, body: {'keepPerFlavor': 0}),
      path: path,
      method: 'PUT',
      status: 400,
    );
    expectContract(
      await send('PUT', path, token: ''),
      path: path,
      method: 'PUT',
      status: 401,
    );
    expectContract(
      await send('PUT', path, token: mcp, body: {'keepPerFlavor': 3}),
      path: path,
      method: 'PUT',
      status: 403,
    );
  });

  test('notification.raised frames match SequencedEvent', () async {
    final notifier = Notifier(
      events: engine.events,
      factory: NoticeFactory(
        projects: engine.projectRepository,
        releases: engine.releaseRepository,
        jobs: engine.jobRepository,
        runs: engine.runRepository,
        masker: const NoMasking(),
      ),
      credentials: engine.credentialRepository,
      secrets: engine.credentialSecrets,
      slack: SlackSender(webhook: FakeSlackWebhook()),
      clock: engine.clock,
    )..start();
    addTearDown(notifier.stop);
    final stream = await engine.connect(after: engine.events.head);
    addTearDown(stream.close);

    engine.events.append(
      const CredentialExpired(
        credentialId: 'crd_1',
        projectId: 'prj_1',
        kind: CredentialKind.slack,
        message: 'The webhook was revoked.',
      ),
    );

    // The first frame opens the stream.
    final received = (await stream.take(3)).skip(1).toList();
    expect(received.map((frame) => frame.event.type), [
      'credential.expired',
      'notification.raised',
    ]);
    final frame = received.last;
    expect(contract.validateSchema('SequencedEvent', frame.toJson()), isEmpty);
    expect(
      frame.event,
      const NotificationRaised(
        kind: NotificationKind.credentialExpired,
        level: NotificationLevel.error,
        title: 'Credential expired: slack',
        body: 'prj_1: The webhook was revoked.',
        projectId: 'prj_1',
      ),
    );
  });
}
