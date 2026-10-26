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

    test('documents the lease of a repository on any git host', () {
      const bitbucket = LeaseRepository(
        cacheKey: 'h0123456789abcdef',
        sshUrl: 'git@bitbucket.org:ws/app.git',
      );

      expect(
        shipped.validateSchema('LeaseRepository', bitbucket.toJson()),
        isEmpty,
      );
      expect(bitbucket.toJson().containsKey('githubRepoId'), isFalse);
      for (final cacheKey in ['', 'h0123', '../7', 'H0123456789ABCDEF']) {
        expect(
          shipped.validateSchema('LeaseRepository', {
            'cacheKey': cacheKey,
            'sshUrl': 'git@bitbucket.org:ws/app.git',
          }),
          isNotEmpty,
          reason: cacheKey,
        );
      }
    });

    test('documents projects on GitHub and on any other host', () {
      const projects = ProjectsResponse([
        Project(
          id: 'prj_1',
          host: Project.githubHost,
          sourceKey: '42',
          githubRepoId: 42,
          fullName: 'acme/shop',
          remote: 'https://github.com/acme/shop.git',
          defaultBaseBranch: 'main',
        ),
        Project(
          id: 'prj_2',
          host: 'bitbucket.org',
          sourceKey: 'h0123456789abcdef',
          fullName: 'ws/group/app',
          remote: 'git@bitbucket.org:ws/group/app.git',
          defaultBaseBranch: 'main',
        ),
      ]);

      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/projects',
          statusCode: 200,
          body: jsonEncode(projects.toJson()),
          contentType: 'application/json',
        ),
        isEmpty,
      );
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

    test('documents the test endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );

      for (final path in [
        '/jobs/job_1/tests',
        '/projects/prj_1/tests/baseline',
      ]) {
        expect(
          shipped.validateResponse(
            method: 'GET',
            path: path,
            statusCode: 401,
            body: unauthorized,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: path,
        );
      }
    });

    test('describes test runs', () {
      const counts = TestCounts(
        total: 3,
        passed: 1,
        failed: 1,
        errored: 1,
        skipped: 0,
      );
      final run = TestRun(
        id: 'tst_1',
        jobId: 'job_1',
        branch: 'main',
        appPath: '.',
        baseline: false,
        createdAt: DateTime.utc(2026),
        counts: counts,
        diff: const TestRunDiff(
          comparedTo: 'job_0',
          newFailures: [TestRef(suite: 'test/a_test.dart', name: 'a')],
          fixed: [],
          missing: [],
          stillFailing: 1,
        ),
      );
      final response = TestRunResponse(
        run: run,
        total: 1,
        offset: 0,
        tests: const [
          TestCase(
            suite: 'test/a_test.dart',
            name: 'a',
            status: TestStatus.failed,
            message: 'm',
            stackTrace: 's',
          ),
        ],
      );
      final baselines = TestBaselinesResponse([
        TestBaseline(
          appPath: '.',
          branch: 'main',
          jobId: 'job_0',
          createdAt: DateTime.utc(2026),
          counts: counts,
        ),
      ]);

      expect(shipped.validateSchema('TestRun', run.toJson()), isEmpty);
      expect(
        shipped.validateSchema('TestRunResponse', response.toJson()),
        isEmpty,
      );
      expect(
        shipped.validateSchema('TestBaselinesResponse', baselines.toJson()),
        isEmpty,
      );
      expect(
        shipped.validateSchema('TestRun', {...run.toJson(), 'diff': null}),
        isNotEmpty,
      );
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

    test('documents the credential endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final rejected = jsonEncode(
        ErrorResponse.of(ApiErrorCode.credentialRejected, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/credentials'),
        ('POST', '/credentials'),
        ('GET', '/credentials/crd_1'),
        ('PATCH', '/credentials/crd_1'),
        ('PUT', '/credentials/crd_1'),
        ('DELETE', '/credentials/crd_1'),
        ('POST', '/credentials/crd_1/verify'),
        ('GET', '/projects/prj_1/credentials'),
        ('PUT', '/projects/prj_1/credentials'),
        ('PUT', '/projects/prj_1/flavors/prod/credentials/asc_key'),
        ('DELETE', '/projects/prj_1/flavors/prod/credentials/asc_key'),
        ('POST', '/projects/prj_1/credentials/crd_1/verify'),
        ('DELETE', '/projects/prj_1/credentials/crd_1'),
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
      expect(
        shipped.validateResponse(
          method: 'PUT',
          path: '/projects/prj_1/credentials',
          statusCode: 422,
          body: rejected,
          contentType: 'application/json',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'DELETE',
          path: '/credentials/crd_1',
          statusCode: 409,
          body: jsonEncode({
            ...ErrorResponse.of(ApiErrorCode.credentialInUse, 'm').toJson(),
            'usedBy': [
              const CredentialUsage(
                projectId: 'prj_1',
                project: 'acme/shop',
                app: '.',
                flavor: 'prod',
                status: CredentialStatus.verified,
              ).toJson(),
            ],
          }),
          contentType: 'application/json',
        ),
        isEmpty,
      );
    });

    test('describes the named credentials and their requests', () {
      final at = DateTime.utc(2026, 10, 18);
      final named = NamedCredential(
        id: 'crd_1',
        name: 'Personal Apple Dev Account',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.verified,
        account: 'ABC123DEF4',
        verifiedAt: at,
        checkedAt: at,
        usedBy: [
          CredentialUsage(
            projectId: 'prj_1',
            project: 'acme/shop',
            app: '.',
            flavor: 'prod',
            status: CredentialStatus.rejected,
            checkedAt: at,
            message: 'm',
            fix: 'f',
          ),
        ],
      );
      expect(
        shipped.validateSchema(
          'NamedCredentialsResponse',
          NamedCredentialsResponse([named]).toJson(),
        ),
        isEmpty,
      );
      const flavor = Credential(
        id: 'crd_1',
        name: 'Personal Apple Dev Account',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.rejected,
        credentialStatus: CredentialStatus.verified,
        assignmentStatus: CredentialStatus.rejected,
      );
      expect(
        shipped.validateSchema(
          'AssignCredentialResponse',
          const AssignCredentialResponse(
            assigned: [flavor],
            kept: [flavor],
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'AssignCredentialRequest',
          const AssignCredentialRequest(
            credentialId: 'crd_1',
            allFlavors: true,
            replace: true,
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'RenameCredentialRequest',
          const RenameCredentialRequest('n').toJson(),
        ),
        isEmpty,
      );
      for (final request in <Map<String, Object?>>[
        {
          'name': 'n',
          'kind': 'asc_key',
          'keyId': 'ABC123DEF4',
          'issuerId': 'uuid',
          'privateKey': 'p8',
        },
        {
          'name': 'n',
          'kind': 'apple_id',
          'appleId': 'a@b.co',
          'password': 'abcd-efgh-ijkl-mnop',
        },
        {'name': 'n', 'kind': 'firebase_sa', 'serviceAccount': '{}'},
        {
          'name': 'n',
          'kind': 'keystore',
          'keystore': 'AQID',
          'storePassword': 'x',
          'keyAlias': 'upload',
        },
        {'name': 'n', 'kind': 'shorebird', 'token': 'sb_api_x'},
        {'name': 'n', 'kind': 'slack', 'webhookUrl': 'https://h'},
      ]) {
        expect(
          shipped.validateSchema('CreateCredentialRequest', request),
          isEmpty,
          reason: '$request',
        );
        final fields = {...request}..remove('name');
        expect(
          shipped.validateSchema('ReplaceCredentialRequest', fields),
          isEmpty,
          reason: '$fields',
        );
      }
      for (final request in <Map<String, Object?>>[
        {'kind': 'shorebird', 'token': 'x'},
        {'name': 'n', 'kind': 'github', 'token': 'x'},
        {'name': 'n', 'kind': 'shorebird', 'token': 'x', 'extra': 1},
      ]) {
        expect(
          shipped.validateSchema('CreateCredentialRequest', request),
          isNotEmpty,
          reason: '$request',
        );
      }
      expect(
        shipped.validateSchema('ReplaceCredentialRequest', {
          'token': 'x',
          'extra': 1,
        }),
        isNotEmpty,
      );
    });

    test('documents the workflow and run endpoints', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final invalid = jsonEncode(
        ErrorResponse.of(ApiErrorCode.workflowInvalid, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/workflows/schema'),
        ('GET', '/projects/prj_1/workflows'),
        ('POST', '/projects/prj_1/workflows'),
        ('POST', '/projects/prj_1/workflows/validate'),
        ('GET', '/projects/prj_1/workflows/wf_1'),
        ('PUT', '/projects/prj_1/workflows/wf_1'),
        ('DELETE', '/projects/prj_1/workflows/wf_1'),
        ('POST', '/projects/prj_1/workflows/wf_1/dispatch'),
        ('GET', '/runs/run_1'),
        ('POST', '/runs/run_1/cancel'),
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
      for (final (method, path) in [
        ('POST', '/projects/prj_1/workflows'),
        ('PUT', '/projects/prj_1/workflows/wf_1'),
        ('POST', '/projects/prj_1/workflows/wf_1/dispatch'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 422,
            body: invalid,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('describes the workflow and run models', () {
      final at = DateTime.utc(2026, 10, 13);
      final version = WorkflowVersionInfo(
        id: 'wfv_1',
        version: 1,
        createdAt: at,
      );
      final workflow = Workflow(
        id: 'wf_1',
        projectId: 'prj_1',
        name: 'test',
        builtin: true,
        version: version,
        versions: [version],
        yaml: 'schema: 1',
      );
      final run = Run(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        ref: 'main',
        state: RunState.waitingForApproval,
        locksProject: true,
        version: '1.0.0',
        build: 7,
        createdAt: at,
        jobs: const [
          RunJob(
            id: 'job_1',
            name: 'prepare',
            stage: 0,
            state: JobState.waitingForApproval,
            capabilities: ['flutter'],
            message: 'm',
          ),
        ],
      );

      expect(shipped.validateSchema('Workflow', workflow.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'WorkflowsResponse',
          WorkflowsResponse([
            WorkflowSummary(
              id: 'wf_1',
              projectId: 'prj_1',
              name: 'test',
              builtin: true,
              version: version,
            ),
          ]).toJson(),
        ),
        isEmpty,
      );
      expect(shipped.validateSchema('Run', run.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'WorkflowSchema',
          const WorkflowSchema(
            schema: 1,
            steps: [
              StepType(
                kind: 'build.android',
                withKeys: ['artifact', 'obfuscate'],
                title: 'Build Android',
                description: 'Builds an APK.',
                group: 'Build',
                capabilities: [
                  ['android', 'flutter'],
                ],
                keys: [
                  StepKeySchema(
                    name: 'artifact',
                    type: StepKeyType.string,
                    options: ['apk', 'aab'],
                    defaultValue: 'apk',
                    description: 'What to build.',
                  ),
                  StepKeySchema(name: 'obfuscate', type: StepKeyType.boolean),
                ],
              ),
            ],
            gates: ['prod_release'],
            gateLabels: {'prod_release': 'Production release'},
            capabilities: ['flutter'],
            matrixAxes: ['platform', 'flavor'],
            platforms: ['android', 'ios'],
            variables: ['flavor', 'flavor.prod'],
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'ValidateWorkflowResponse',
          const ValidateWorkflowResponse(
            valid: false,
            issues: [WorkflowIssue(line: 1, column: 1, message: 'm')],
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'DispatchRequest',
          const DispatchRequest(
            ref: 'main',
            flavors: ['dev'],
            platforms: ['android'],
            bump: VersionBump.patch,
            version: '1.2.3',
            releaseVersion: '1.2.0+4',
            inputs: {'a': 1},
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'CreateWorkflowRequest',
          const CreateWorkflowRequest(name: 'my.flow', yaml: 'y').toJson(),
        ),
        isEmpty,
      );
    });

    test('documents the approval and gate endpoints', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final forbidden = jsonEncode(
        ErrorResponse.of(ApiErrorCode.forbidden, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/approvals'),
        ('GET', '/approvals/apr_1'),
        ('POST', '/approvals/apr_1/approve'),
        ('POST', '/approvals/apr_1/deny'),
        ('GET', '/projects/prj_1/gates'),
        ('PUT', '/projects/prj_1/gates'),
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
      for (final (method, path) in [
        ('POST', '/approvals/apr_1/approve'),
        ('POST', '/approvals/apr_1/deny'),
        ('PUT', '/projects/prj_1/gates'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 403,
            body: forbidden,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('describes the approval models', () {
      final at = DateTime.utc(2026, 10, 13);
      final approval = Approval(
        id: 'apr_1',
        projectId: 'prj_1',
        action: 'prod_release',
        sha: 'a' * 40,
        version: '1.2.3+45',
        runId: 'run_1',
        jobId: 'job_1',
        state: ApprovalState.approved,
        createdAt: at,
        expiresAt: at.add(const Duration(hours: 24)),
        decidedAt: at,
        decidedBy: const DecidedBy(
          tokenId: 'tok_1',
          name: 'Mac mini',
          kind: DeviceTokenKind.app,
        ),
        reason: 'ok',
      );

      expect(shipped.validateSchema('Approval', approval.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'ApprovalsResponse',
          ApprovalsResponse([approval]).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema('AlreadyDecidedResponse', {
          ...ErrorResponse.of(ApiErrorCode.alreadyDecided, 'm').toJson(),
          'approval': approval.toJson(),
        }),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'DecisionRequest',
          const DecisionRequest(reason: 'ok').toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'ProjectGates',
          const ProjectGates({'prod_release': false, 'push': true}).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema('ProjectGates', {
          'gates': {'launch_rocket': true},
        }),
        isNotEmpty,
      );
      expect(
        shipped.validateSchema('Approval', {
          ...approval.toJson(),
          'decidedBy': {'tokenId': 't', 'name': 'n', 'kind': 'mcp'},
        }),
        isNotEmpty,
      );
    });

    test('documents the release endpoints', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final forbidden = jsonEncode(
        ErrorResponse.of(ApiErrorCode.forbidden, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/releases'),
        ('GET', '/releases/rel_1'),
        ('POST', '/releases/rel_1/refresh'),
        ('POST', '/releases/rel_1/stores/apple/status'),
        ('POST', '/releases/rel_1/builds'),
        ('POST', '/releases/rel_1/merge'),
        ('POST', '/releases/rel_1/abandon'),
        ('GET', '/releases/rel_1/notes'),
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
      for (final (method, path) in [
        ('POST', '/releases/rel_1/stores/play/status'),
        ('POST', '/releases/rel_1/abandon'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 403,
            body: forbidden,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    });

    test('describes the release models', () {
      final at = DateTime.utc(2026, 10, 14);
      final release = Release(
        id: 'rel_1',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        version: '1.2.0',
        build: 45,
        state: ReleaseState.live,
        stores: [
          StoreStatus(
            store: ReleaseStore.apple,
            state: StoreState.live,
            source: StatusSource.api,
            detail: 'READY_FOR_DISTRIBUTION',
            checkedAt: at,
            changedAt: at,
            note: 'n',
          ),
        ],
        builds: [ReleaseBuild(build: 45, runId: 'run_1', createdAt: at)],
        mergeEnabled: true,
        branch: 'release/1.2.0',
        baseBranch: 'main',
        tag: 'v1.2.0+45',
        headSha: 'a' * 40,
        prNumber: 7,
        prUrl: 'https://github.com/o/r/pull/7',
        mergeCommit: 'b' * 40,
        mergeRunId: 'run_2',
        message: 'm',
        whatsNew: 'New',
        whatToTest: 'Try it',
        createdAt: at,
        updatedAt: at,
      );

      expect(shipped.validateSchema('Release', release.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'ReleasesResponse',
          ReleasesResponse([release]).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'StoreStatusRequest',
          const StoreStatusRequest(state: StoreState.live).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema('StoreStatusRequest', {'state': 'rejected'}),
        isNotEmpty,
      );
      expect(
        shipped.validateSchema(
          'AbandonRequest',
          const AbandonRequest(reason: 'r').toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema('Release', {...release.toJson(), 'state': 'x'}),
        isNotEmpty,
      );
    });

    test('describes the rollout, history, texts and patch models', () {
      final at = DateTime.utc(2026, 10, 26);
      for (final request in [
        for (final action in RolloutAction.values)
          RolloutRequest(
            store: ReleaseStore.play,
            action: action,
            userFraction: action == RolloutAction.fraction ? 0.5 : null,
          ),
        const RolloutRequest(
          store: ReleaseStore.play,
          action: RolloutAction.fraction,
          userFraction: 1,
        ),
      ]) {
        expect(
          shipped.validateSchema('RolloutRequest', request.toJson()),
          isEmpty,
          reason: '$request',
        );
      }
      for (final fraction in [0, 1.5]) {
        expect(
          shipped.validateSchema('RolloutRequest', {
            'store': 'play',
            'action': 'fraction',
            'userFraction': fraction,
          }),
          isNotEmpty,
          reason: '$fraction',
        );
      }
      final history = ReleaseHistory([
        for (final kind in ReleaseEventKind.values)
          ReleaseEvent(
            kind: kind,
            at: at,
            store: ReleaseStore.apple,
            detail: 'd',
            by: 'MacBook',
            runId: 'run_1',
            patchNumber: 1,
          ),
      ]);
      expect(
        shipped.validateSchema('ReleaseHistory', history.toJson()),
        isEmpty,
      );
      expect(
        shipped.validateSchema('ReleaseEvent', {
          'kind': 'launched',
          'at': '$at',
        }),
        isNotEmpty,
      );
      expect(
        shipped.validateSchema(
          'ReleaseTexts',
          const ReleaseTexts(whatsNew: 'New', whatToTest: 'Try').toJson(),
        ),
        isEmpty,
      );
      for (final action in PatchAction.values) {
        expect(
          shipped.validateSchema('PatchAction', action.wire),
          isEmpty,
          reason: action.wire,
        );
      }
    });

    test('describes the token, status and doctor models', () {
      final info = TokenInfo(
        id: 'tok_1',
        name: 'xp on MacBook',
        kind: DeviceTokenKind.cli,
        createdAt: DateTime.utc(2026, 10, 26),
      );
      expect(
        shipped.validateSchema(
          'CreateTokenRequest',
          const CreateTokenRequest(
            name: 'xp on MacBook',
            kind: DeviceTokenKind.mcp,
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'CreatedToken',
          CreatedToken(info: info, token: 'xpt_x').toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'StatusResponse',
          StatusResponse(token: info, secretsLocked: false).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'DoctorResponse',
          DoctorResponse([
            for (final state in CheckState.values)
              EngineCheck(name: 'git', state: state, detail: 'd', fix: 'f'),
          ]).toJson(),
        ),
        isEmpty,
      );
    });

    test('describes every kind of credential request', () {
      const requests = <Map<String, Object?>>[
        {
          'flavor': 'prod',
          'kind': 'asc_key',
          'keyId': 'ABC123DEF4',
          'issuerId': 'uuid',
          'privateKey': 'p8',
          'keyKind': 'individual',
        },
        {
          'flavor': 'prod',
          'kind': 'apple_id',
          'appleId': 'a@b.co',
          'password': 'abcd-efgh-ijkl-mnop',
        },
        {'flavor': 'prod', 'kind': 'play_sa', 'serviceAccount': '{}'},
        {
          'app': '.',
          'flavor': 'prod',
          'kind': 'firebase_sa',
          'serviceAccount': '{}',
        },
        {
          'flavor': 'prod',
          'kind': 'keystore',
          'keystore': 'AQID',
          'storePassword': 'x',
          'keyAlias': 'upload',
          'keyPassword': 'y',
        },
        {'flavor': 'prod', 'kind': 'shorebird', 'token': 'sb_api_x'},
        {'flavor': 'prod', 'kind': 'github', 'token': 'ghp_x'},
        {
          'flavor': 'prod',
          'kind': 'slack',
          'name': 'Team Slack',
          'webhookUrl': 'https://hooks.slack.com/services/T/B/X',
        },
      ];
      for (final request in requests) {
        expect(
          shipped.validateSchema('SaveCredentialRequest', request),
          isEmpty,
          reason: '$request',
        );
      }
      for (final request in <Map<String, Object?>>[
        {'flavor': 'prod', 'kind': 'asc_key', 'keyId': 'x'},
        {'flavor': 'prod', 'kind': 'dropbox', 'token': 'x'},
        {'flavor': 'prod', 'kind': 'github', 'token': 'x', 'extra': 1},
        {'kind': 'github', 'token': 'x'},
      ]) {
        expect(
          shipped.validateSchema('SaveCredentialRequest', request),
          isNotEmpty,
          reason: '$request',
        );
      }
    });

    test('documents the runner endpoints', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final forbidden = jsonEncode(
        ErrorResponse.of(ApiErrorCode.forbidden, 'm').toJson(),
      );
      final conflict = jsonEncode(
        ErrorResponse.of(ApiErrorCode.conflict, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/runners'),
        ('POST', '/runners/pairing-tokens'),
        ('POST', '/runners/pair'),
        ('POST', '/runners/rnr_1/revoke'),
        ('GET', '/runners/connect'),
        ('GET', '/runners/bundle'),
        ('PUT', '/runners/jobs/job_1/artifacts/a.apk'),
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
      for (final (method, path) in [
        ('POST', '/runners/pairing-tokens'),
        ('POST', '/runners/rnr_1/revoke'),
        ('GET', '/runners/connect'),
        ('PUT', '/runners/jobs/job_1/artifacts/a.apk'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 403,
            body: forbidden,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
      for (final (method, path) in [
        ('POST', '/runners/pairing-tokens'),
        ('POST', '/runners/pair'),
        ('PUT', '/runners/jobs/job_1/artifacts/a.apk'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 409,
            body: conflict,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/runners/connect',
          statusCode: 101,
          body: '',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/runners/bundle',
          statusCode: 200,
          body: 'bytes',
          contentType: 'application/gzip',
        ),
        isEmpty,
      );
      for (final (status, code) in [
        (400, ApiErrorCode.invalidRequest),
        (404, ApiErrorCode.notFound),
      ]) {
        expect(
          shipped.validateResponse(
            method: 'GET',
            path: '/runners/bundle',
            statusCode: status,
            body: jsonEncode(ErrorResponse.of(code, 'm').toJson()),
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$status',
        );
      }
    });

    test('describes the runner models', () {
      final at = DateTime.utc(2026, 10, 14);
      final runner = Runner(
        id: 'rnr_1',
        name: 'mac-mini',
        status: RunnerStatus.online,
        capabilities: const ['flutter', 'ios-sign'],
        slots: 2,
        jobIds: const ['job_1'],
        os: 'macos',
        arch: 'arm64',
        version: '1.0.0',
        cores: 8,
        lastHeartbeat: at,
        createdAt: at,
        revokedAt: at,
      );

      expect(shipped.validateSchema('Runner', runner.toJson()), isEmpty);
      expect(
        shipped.validateSchema(
          'RunnersResponse',
          RunnersResponse([runner]).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'CreatePairingTokenRequest',
          const CreatePairingTokenRequest(name: 'mac-mini').toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'PairingToken',
          PairingToken(
            token: 'xpp_x',
            name: 'mac-mini',
            expiresAt: at,
          ).toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'PairRunnerRequest',
          const PairRunnerRequest(pairingToken: 'xpp_x').toJson(),
        ),
        isEmpty,
      );
      expect(
        shipped.validateSchema(
          'PairRunnerResponse',
          PairRunnerResponse(runner: runner, token: 'xpt_x').toJson(),
        ),
        isEmpty,
      );
      expect(shipped.validateSchema('Runner', {'id': 'rnr_1'}), isNotEmpty);
    });

    test('describes every frame of the runner protocol', () {
      final at = DateTime.utc(2026, 10, 14);
      const lease = LeaseRef(jobId: 'job_1', leaseId: 'lse_1');
      final fromRunner = <RunnerFrame>[
        const HelloFrame(
          version: '1.0.0',
          os: 'macos',
          arch: 'arm64',
          cores: 8,
          maxJobs: 2,
          leases: [lease],
        ),
        const ProbeResultFrame(
          probeId: 'prb_1',
          results: [
            ProbeResult(
              id: 'git',
              status: ProbeStatus.exited,
              exitCode: 0,
              stdout: 'git version 2',
            ),
            ProbeResult(id: 'swift', status: ProbeStatus.notStarted),
          ],
        ),
        const ProbeResultFrame(
          probeId: 'prb_2',
          results: [
            ProbeResult(
              id: 'ios_linux_commit',
              status: ProbeStatus.exited,
              exitCode: 0,
              stdout: 'abc\n',
            ),
          ],
          iosLinuxDir: '/home/me/omarchy-apple-dev',
        ),
        const LeaseAcceptFrame(jobId: 'job_1', leaseId: 'lse_1'),
        const LeaseRejectFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          reason: 'busy',
        ),
        const HeartbeatFrame(leases: [lease]),
        LogChunkFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          seq: 1,
          lines: [
            ChunkLine(step: 0, at: at, stream: LogStream.stdout, text: 'hi'),
          ],
        ),
        StepStateFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          ordinal: 0,
          state: StepState.succeeded,
          attempts: 1,
          result: const {'a': 1},
          message: 'ok',
          startedAt: at,
          finishedAt: at,
        ),
        const JobDoneFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          state: JobState.failed,
          lastChunk: 1,
          message: 'boom',
        ),
        const SecretRequestFrame(jobId: 'job_1', leaseId: 'lse_1', key: 'k'),
        const DrainFrame(),
      ];
      final fromEngine = <EngineFrame>[
        const WelcomeFrame(
          runnerId: 'rnr_1',
          engineVersion: '1.0.0',
          apiVersion: '1',
        ),
        const ProbeFrame(
          probeId: 'prb_1',
          commands: [
            ProbeCommand(
              id: 'git',
              executable: 'git',
              arguments: ['--version'],
            ),
            ProbeCommand(
              id: 'xcodebuild',
              executable: 'xcodebuild',
              arguments: ['-version'],
              requires: 'xcode_select',
              onlyOn: 'macos',
            ),
          ],
        ),
        const ProbedFrame(
          capabilities: ['flutter', 'ios-linux'],
          missing: [
            MissingCapability(
              capability: 'ios-linux',
              reason: 'no darwin SDK bundle',
              fix: 'run install-toolchain.sh',
            ),
          ],
        ),
        LeaseOfferFrame(
          leaseId: 'lse_1',
          jobId: 'job_1',
          projectId: 'prj_1',
          sha: 'a' * 40,
          name: 'Build',
          repository: const LeaseRepository(
            cacheKey: '7',
            sshUrl: 'git@github.com:owner/app.git',
          ),
          stage: 0,
          capabilities: const ['android'],
          expiresAt: at,
          steps: const [
            LeaseStep(
              ordinal: 0,
              kind: 'build.android',
              sideEffect: false,
              state: StepState.pending,
              attempts: 0,
              input: {'artifact': 'aab'},
            ),
          ],
          secrets: const ['keystore'],
        ),
        HeartbeatAckFrame(
          leases: [LeaseGrant(jobId: 'job_1', leaseId: 'lse_1', until: at)],
        ),
        const ChunkAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          seq: 2,
          next: 1,
          status: ChunkStatus.gap,
        ),
        const DoneAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          state: JobState.succeeded,
        ),
        const CancelFrame(jobId: 'job_1', leaseId: 'lse_1', reason: 'r'),
        const SecretValueFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'k',
          value: 'v',
        ),
        const SecretDeniedFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'k',
          reason: 'r',
        ),
        const FaultFrame(code: 'invalid_frame', message: 'm'),
      ];

      for (final frame in fromRunner) {
        expect(
          shipped.validateSchema(
            'RunnerFrame',
            jsonDecode(jsonEncode(frame.toJson())),
          ),
          isEmpty,
          reason: frame.type,
        );
      }
      for (final frame in fromEngine) {
        expect(
          shipped.validateSchema(
            'EngineFrame',
            jsonDecode(jsonEncode(frame.toJson())),
          ),
          isEmpty,
          reason: frame.type,
        );
      }
      expect(
        shipped.validateSchema('RunnerFrame', {'type': 'warp'}),
        isNotEmpty,
      );
      expect(
        shipped.validateSchema('RunnerFrame', {
          'type': 'job_done',
          'jobId': 'j',
          'leaseId': 'l',
          'state': 'running',
          'lastChunk': 0,
        }),
        isNotEmpty,
      );
    });

    test('documents the storage endpoints', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );
      final forbidden = jsonEncode(
        ErrorResponse.of(ApiErrorCode.forbidden, 'm').toJson(),
      );
      final invalid = jsonEncode(
        ErrorResponse.of(ApiErrorCode.invalidRequest, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/storage'),
        ('POST', '/storage/free'),
        ('GET', '/storage/retention'),
        ('PUT', '/storage/retention'),
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
      for (final (method, path, status, body) in [
        ('POST', '/storage/free', 403, forbidden),
        ('PUT', '/storage/retention', 403, forbidden),
        ('POST', '/storage/free', 400, invalid),
        ('PUT', '/storage/retention', 400, invalid),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: status,
            body: body,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path $status',
        );
      }
    });

    test('describes the storage and release notes models', () {
      final report = StorageReport(
        generatedAt: DateTime.utc(2026, 10, 14),
        categories: const [
          CategoryUsage(
            category: StorageCategory.artifacts,
            usedBytes: 10,
            reclaimableBytes: 4,
            items: 1,
          ),
        ],
        flavors: const [
          FlavorUsage(
            projectId: 'prj_1',
            app: '.',
            flavor: '',
            builds: 1,
            artifacts: 1,
            usedBytes: 10,
            reclaimableBytes: 4,
          ),
        ],
        retention: const RetentionSettings(),
      );
      const free = FreeSpaceResult(
        dryRun: true,
        categories: [
          FreedCategory(category: StorageCategory.logs, bytes: 1, items: 1),
        ],
        failures: ['x'],
      );
      const notes = ReleaseNotes(
        releaseId: 'rel_1',
        version: '1.2.0',
        build: 45,
        from: 'v1.1.0+40',
        to: 'abc',
        commits: 1,
        groups: [
          ReleaseNoteGroup(
            type: 'feat',
            title: 'Features',
            items: [ReleaseNoteItem(sha: 'abc', description: 'a', scope: 'ui')],
          ),
        ],
        compareUrl: 'https://github.com/o/r/compare/a...b',
        slack: '*Features*',
        whatsapp: '*Features*',
      );

      for (final (schema, json) in <(String, Object)>[
        ('StorageReport', report.toJson()),
        ('RetentionSettings', const RetentionSettings().toJson()),
        ('RetentionSettings', <String, Object>{}),
        ('FreeSpaceRequest', const FreeSpaceRequest().toJson()),
        (
          'FreeSpaceRequest',
          const FreeSpaceRequest(
            dryRun: false,
            categories: [StorageCategory.mirrors],
          ).toJson(),
        ),
        ('FreeSpaceResult', free.toJson()),
        ('ReleaseNotes', notes.toJson()),
      ]) {
        expect(shipped.validateSchema(schema, json), isEmpty, reason: schema);
      }
      expect(
        shipped.validateSchema('RetentionSettings', {'keepPerFlavor': 0}),
        isNotEmpty,
      );
      expect(
        shipped.validateSchema('FreeSpaceRequest', {
          'categories': ['unicorns'],
        }),
        isNotEmpty,
      );
    });

    test('describes every event the engine can send', () {
      for (final event in <EngineEvent>[
        const EngineStarted(version: '0.0.1', apiVersion: '1'),
        const StreamOpened(),
        const ProjectAdded(projectId: 'prj_1', fullName: 'o/r'),
        const ProjectScanned(projectId: 'prj_1', errors: 0, warnings: 1),
        const ProjectEdited(projectId: 'prj_1'),
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
        const TestRunCompleted(
          jobId: 'job_1',
          projectId: 'prj_1',
          branch: 'main',
          baseline: false,
          failures: 3,
          newFailures: 1,
        ),
        const CredentialSaved(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.ascKey,
          replaced: false,
        ),
        const CredentialVerified(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.ascKey,
          status: CredentialStatus.verified,
        ),
        const CredentialExpired(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.ascKey,
          message: 'Revoked.',
        ),
        const CredentialRemoved(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.ascKey,
        ),
        const CredentialRenamed(
          credentialId: 'crd_1',
          kind: CredentialKind.ascKey,
          name: 'Personal Apple Dev Account',
        ),
        const CredentialAssigned(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
        ),
        const CredentialUnassigned(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
        ),
        const WorkflowSaved(
          workflowId: 'wf_1',
          projectId: 'prj_1',
          name: 'dev-build',
          version: 1,
        ),
        const WorkflowRemoved(
          workflowId: 'wf_1',
          projectId: 'prj_1',
          name: 'dev-build',
        ),
        const RunDispatched(
          runId: 'run_1',
          projectId: 'prj_1',
          workflowId: 'wf_1',
          jobIds: ['job_1'],
        ),
        const ReleaseCreated(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          flavor: 'prod',
          version: '1.2.0',
          build: 45,
        ),
        const ReleaseStateChanged(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          from: ReleaseState.uploaded,
          to: ReleaseState.inReview,
        ),
        const ReleaseStoreChanged(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          store: ReleaseStore.play,
          state: StoreState.live,
          source: StatusSource.api,
        ),
        const NotificationRaised(
          kind: NotificationKind.approvalRequested,
          level: NotificationLevel.warning,
          title: 'Approval needed',
          body: 'Release 1.2.0.',
          projectId: 'prj_1',
          approvalId: 'apr_1',
        ),
        const RunnerPaired(runnerId: 'rnr_1', name: 'mac-mini'),
        const RunnerConnected(
          runnerId: 'rnr_1',
          name: 'mac-mini',
          capabilities: ['flutter'],
          slots: 1,
        ),
        const RunnerDisconnected(runnerId: 'rnr_1', name: 'mac-mini'),
        const RunnerRevoked(runnerId: 'rnr_1', name: 'mac-mini'),
        const RunnerCapabilitiesChanged(
          runnerId: 'rnr_1',
          name: 'mac-mini',
          from: [],
          to: ['flutter'],
        ),
        const RunnerLeaseLost(
          runnerId: 'rnr_1',
          jobId: 'job_1',
          projectId: 'prj_1',
          reason: 'lapsed',
          state: JobState.queued,
        ),
        const RunnerSecretDelivered(
          runnerId: 'rnr_1',
          jobId: 'job_1',
          key: 'k',
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
