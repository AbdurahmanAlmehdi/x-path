@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('the shipped openapi.yaml', () {
    late OpenApiContract shipped;

    setUpAll(() async => shipped = await OpenApiContract.load());

    test('documents /health, /version and /events', () {
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/health',
          statusCode: 200,
          body: jsonEncode(const HealthResponse().toJson()),
          contentType: 'application/json',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/version',
          statusCode: 200,
          body: jsonEncode(
            const VersionResponse(version: '1', apiVersion: '1').toJson(),
          ),
          contentType: 'application/json',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/events',
          statusCode: 101,
          body: '',
        ),
        isEmpty,
      );
    });

    test('documents the project endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/projects'),
        ('POST', '/projects'),
        ('GET', '/projects/prj_1'),
        ('PATCH', '/projects/prj_1'),
        ('DELETE', '/projects/prj_1'),
        ('POST', '/projects/prj_1/scan'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 401,
            body: unauthorized,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('documents the job endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/jobs/job_1'),
        ('POST', '/jobs/job_1/cancel'),
        ('POST', '/jobs/job_1/resume'),
        ('GET', '/jobs/job_1/logs'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 401,
            body: unauthorized,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('documents the artifact endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/jobs/job_1/artifacts'),
        ('GET', '/artifacts/art_1'),
        ('GET', '/artifacts/art_1/download'),
        ('POST', '/artifacts/art_1/pin'),
        ('POST', '/artifacts/art_1/unpin'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 401,
            body: unauthorized,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('describes artifacts', () {
      final artifact = Artifact(
        id: 'art_1',
        jobId: 'job_1',
        kind: ArtifactKind.shorebirdSymbols,
        name: 'symbols.zip',
        size: 0,
        sha256: 'f' * 64,
        pinned: false,
        createdAt: DateTime.utc(2026),
      );

      expect(shipped.validateSchema('Artifact', artifact.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'ArtifactsResponse',
          ArtifactsResponse([artifact]).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema('Artifact', {
          ...artifact.toJson(),
          'sha256': 'not a digest',
        }),
        isNotEmpty,
      );
    });

    test('describes jobs and log frames', () {
      final job = Job(
        id: 'job_1',
        projectId: 'prj_1',
        workflowVersionId: 'wfv_1',
        state: JobState.waitingForResume,
        createdAt: DateTime.utc(2026),
        steps: const [
          JobStep(
            ordinal: 0,
            kind: 'command',
            state: StepState.interrupted,
            sideEffect: true,
            attempts: 1,
            result: {'exitCode': 0},
          ),
        ],
      );
      expect(shipped.validateSchema('Job', job.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'ResumeJobRequest',
          const ResumeJobRequest(fromStep: 1).toJson(),
        ),
        isEmpty,
      );
      for (final frame in <LogFrame>[
        LogLineFrame(
          seq: 1,
          step: 0,
          at: DateTime.utc(2026),
          stream: LogStream.stdout,
          text: 'hello',
        ),
        const LogGapFrame(fromSeq: 2, toSeq: 4, count: 3),
        const LogEndFrame(state: JobState.succeeded),
      ]) {
        expect(shipped.validateSchema('LogFrame', frame.toJson()), isEmpty);
      }
    });

    test('has an error code for every ApiErrorCode', () {
      for (final code in ApiErrorCode.values) {
        final body = ErrorResponse.of(code, 'm').toJson();

        expect(shipped.validateSchema('ErrorResponse', body), isEmpty);
      }
    });

    test('describes every event the engine can send', () {
      for (final event in <EngineEvent>[
        const EngineStarted(version: '0.0.1', apiVersion: '1'),
        const StreamOpened(),
        const ProjectAdded(projectId: 'prj_1', fullName: 'o/r'),
        const ProjectScanned(projectId: 'prj_1', errors: 0, warnings: 1),
        const ProjectRemoved(projectId: 'prj_1'),
        const JobStateChanged(
          jobId: 'job_1',
          projectId: 'prj_1',
          state: JobState.waitingForResume,
        ),
        const JobStepChanged(
          jobId: 'job_1',
          ordinal: 0,
          kind: 'command',
          state: StepState.running,
        ),
      ]) {
        final json = SequencedEvent(
          seq: 1,
          at: DateTime.utc(2026),
          event: event,
        ).toJson();

        expect(shipped.validateSchema('SequencedEvent', json), isEmpty);
      }
    });
  });
}
