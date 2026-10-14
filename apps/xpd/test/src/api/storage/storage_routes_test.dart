import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;
  late Map<DeviceTokenKind, String> secrets;

  setUp(() async {
    engine = await TestEngine.start();
    secrets = {
      DeviceTokenKind.app: engine.secret,
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ])
        kind: (await engine.tokens.issue(
          name: '${kind.name} token',
          kind: kind,
        )).secret,
    };
  });

  tearDown(() => engine.close());

  Future<RawResponse> send(
    String method,
    String path, {
    DeviceTokenKind kind = DeviceTokenKind.app,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: secrets[kind],
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  ErrorResponse errorOf(RawResponse response) =>
      ErrorResponse.fromJson(response.json);

  /// Seven finished builds of the same flavor, one file each.
  Future<void> addBuilds() async {
    for (var day = 1; day <= 7; day++) {
      final id = 'job_$day';
      await engine.jobRepository.create(
        JobRecord(
          id: id,
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.succeeded,
          createdAt: engine.clock.now().subtract(Duration(days: day)),
          finishedAt: engine.clock.now().subtract(Duration(days: day)),
          runId: 'run_$id',
        ),
        const [],
      );
      await engine.addArtifact(id, name: 'app-$day.apk', content: 'x' * 10);
    }
  }

  group('GET /storage', () {
    test('reports what the engine keeps and what could be freed', () async {
      await addBuilds();
      engine.dataFiles.mirrorList.add(
        const MirrorDirectory(githubRepoId: 9, path: '/m/9.git', bytes: 500),
      );

      final response = await send('GET', '/storage');

      expect(response.statusCode, 200);
      final report = StorageReport.fromJson(response.json);
      expect(report.categories.map((c) => c.category), StorageCategory.values);
      final artifacts = report.categories.first;
      expect(artifacts.usedBytes, 70);
      expect(artifacts.reclaimableBytes, 20);
      expect(report.categories[3].reclaimableBytes, 500);
      expect(report.flavors.single.builds, 7);
      expect(report.retention, const RetentionSettings());
    });

    test(
      'is open to an app, a cli and an mcp token and deletes nothing',
      () async {
        await addBuilds();

        for (final kind in DeviceTokenKind.values) {
          expect(
            (await send('GET', '/storage', kind: kind)).statusCode,
            kind == DeviceTokenKind.runner ? 403 : 200,
            reason: kind.name,
          );
        }
        expect(engine.artifactStore.files, hasLength(7));
      },
    );

    test('needs a token', () async {
      final response = await engine.request('/storage', token: '');

      expect(response.statusCode, 401);
    });
  });

  group('POST /storage/free', () {
    test('is a dry run without a body', () async {
      await addBuilds();

      final response = await send('POST', '/storage/free');

      expect(response.statusCode, 200);
      final result = FreeSpaceResult.fromJson(response.json);
      expect(result.dryRun, isTrue);
      expect(result.categories.first.bytes, 20);
      expect(engine.artifactStore.files, hasLength(7));
    });

    test('is a dry run for an agent, and not for a runner', () async {
      await addBuilds();

      final agent = await send(
        'POST',
        '/storage/free',
        kind: DeviceTokenKind.mcp,
        body: {'dryRun': true},
      );
      final runner = await send(
        'POST',
        '/storage/free',
        kind: DeviceTokenKind.runner,
        body: {'dryRun': true},
      );

      expect(agent.statusCode, 200);
      expect(runner.statusCode, 403);
    });

    test('deletes for the app and for xp', () async {
      await addBuilds();

      final first = await send(
        'POST',
        '/storage/free',
        body: {
          'dryRun': false,
          'categories': ['artifacts'],
        },
      );
      final second = await send(
        'POST',
        '/storage/free',
        kind: DeviceTokenKind.cli,
        body: {'dryRun': false},
      );

      expect(first.statusCode, 200);
      final result = FreeSpaceResult.fromJson(first.json);
      expect(result.dryRun, isFalse);
      expect(result.categories.single.items, 2);
      expect(result.bytes, 20);
      expect(second.statusCode, 200);
      expect(engine.artifactStore.files, hasLength(5));
    });

    test('does not delete for an agent or a runner (D-13)', () async {
      await addBuilds();

      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await send(
          'POST',
          '/storage/free',
          kind: kind,
          body: {'dryRun': false},
        );

        expect(response.statusCode, 403, reason: kind.name);
        expect(errorOf(response).error.code, ApiErrorCode.forbidden);
        expect(errorOf(response).error.message, contains('${kind.name} token'));
      }
      expect(engine.artifactStore.files, hasLength(7));
    });

    test('answers 400 for a body it cannot read', () async {
      for (final rawBody in [
        'nope',
        '[]',
        '{"dryRun": "yes"}',
        '{"categories": ["unicorns"]}',
        '{"categories": "artifacts"}',
      ]) {
        final response = await send('POST', '/storage/free', rawBody: rawBody);

        expect(response.statusCode, 400, reason: rawBody);
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
    });
  });

  group('retention', () {
    test('is 5 builds per flavor and 90 days until changed', () async {
      final response = await send('GET', '/storage/retention');

      expect(response.statusCode, 200);
      expect(response.json, {'keepPerFlavor': 5, 'logDays': 90});
    });

    test('is set by the app and by xp, and the report follows', () async {
      for (final (kind, keep) in [
        (DeviceTokenKind.app, 3),
        (DeviceTokenKind.cli, 2),
      ]) {
        final response = await send(
          'PUT',
          '/storage/retention',
          kind: kind,
          body: {'keepPerFlavor': keep, 'logDays': 30},
        );

        expect(response.statusCode, 200);
        expect(response.json, {'keepPerFlavor': keep, 'logDays': 30});
      }
      await addBuilds();

      final report = StorageReport.fromJson(
        (await send('GET', '/storage')).json,
      );

      expect(report.retention.keepPerFlavor, 2);
      expect(report.flavors.single.reclaimableBytes, 50);
      expect(
        (await send(
          'GET',
          '/storage/retention',
          kind: DeviceTokenKind.mcp,
        )).json,
        {'keepPerFlavor': 2, 'logDays': 30},
      );
    });

    test('is not set by an agent or a runner', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        final response = await send(
          'PUT',
          '/storage/retention',
          kind: kind,
          body: {'keepPerFlavor': 1},
        );

        expect(response.statusCode, 403);
        expect(errorOf(response).error.code, ApiErrorCode.forbidden);
      }
      expect(
        (await send('GET', '/storage/retention')).json['keepPerFlavor'],
        5,
      );
    });

    test('answers 400 for a number below 1 or a body it cannot read', () async {
      for (final body in [
        {'keepPerFlavor': 0},
        {'logDays': 0},
        {'keepPerFlavor': 'many'},
      ]) {
        final response = await send('PUT', '/storage/retention', body: body);

        expect(response.statusCode, 400, reason: '$body');
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
      final empty = await send('PUT', '/storage/retention');
      expect(empty.statusCode, 400);
    });
  });
}
