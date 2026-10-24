import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

void main() {
  late RunnerHarness h;
  late FakeRunner runner;

  setUp(() async {
    h = await RunnerHarness.create();
    runner = await h.online();
  });
  tearDown(() => expect(h.errors, isEmpty));

  const checkout = StepPlan(
    kind: 'git.checkout',
    input: {'worktree': <String, dynamic>{}},
    sideEffect: false,
  );

  Future<LeaseOfferFrame> offered({List<StepPlan>? steps}) async {
    await h.job(needs: ['ios-sign'], steps: steps ?? [checkout]);
    await h.scheduler.pump();
    return runner.offer;
  }

  group('the source in the offer (ADR 0009)', () {
    test('names the SSH URL, the repository id and the exact commit', () async {
      final offer = await offered();

      expect(
        offer.repository,
        const LeaseRepository(
          cacheKey: '7',
          githubRepoId: 7,
          sshUrl: 'git@github.com:owner/app.git',
        ),
      );
      expect(offer.sha, 'a' * 40);
    });

    test('carries no credential, whatever the project remote has', () async {
      final project = (await h.projects.get('prj_1'))!;
      await h.projects.update(
        project.copyWith(
          remote: 'https://x-access-token:ghp_secret@host/r.git',
        ),
      );

      final offer = await offered();

      expect(offer.repository!.sshUrl, 'https://host/r.git');
      expect(
        offer.toJson().toString(),
        isNot(anyOf(contains('ghp_secret'), contains('x-access-token'))),
      );
    });

    test('sends a remote that is not on GitHub as it is', () async {
      final project = (await h.projects.get('prj_1'))!;
      await h.projects.update(project.copyWith(remote: '/srv/git/app.git'));

      final offer = await offered();

      expect(offer.repository!.sshUrl, '/srv/git/app.git');
    });

    test('keeps the user of an ssh:// URL', () async {
      final project = (await h.projects.get('prj_1'))!;
      await h.projects.update(
        project.copyWith(remote: 'ssh://git@example.com/r.git'),
      );

      final offer = await offered();

      expect(offer.repository!.sshUrl, 'ssh://git@example.com/r.git');
    });

    test('drops the password of an ssh:// URL', () async {
      final project = (await h.projects.get('prj_1'))!;
      await h.projects.update(
        project.copyWith(remote: 'ssh://git:secret@example.com/r.git'),
      );

      final offer = await offered();

      expect(offer.repository!.sshUrl, 'ssh://example.com/r.git');
    });

    test('keys the cache of a project on another host by its source key '
        '(ADR 0015)', () async {
      final project = (await h.projects.get('prj_1'))!;
      await h.projects.update(
        ProjectRecord(
          id: project.id,
          host: 'bitbucket.org',
          sourceKey: 'h0123456789abcdef',
          fullName: 'ws/app',
          remote: 'git@bitbucket.org:ws/app.git',
          githubDefaultBranch: project.githubDefaultBranch,
          scan: project.scan,
          findings: project.findings,
          scannedAt: project.scannedAt,
        ),
      );

      final offer = await offered();

      expect(
        offer.repository,
        const LeaseRepository(
          cacheKey: 'h0123456789abcdef',
          sshUrl: 'git@bitbucket.org:ws/app.git',
        ),
      );
      expect(offer.repository!.toJson(), isNot(contains('githubRepoId')));
    });

    test('names no repository for a project the engine forgot', () async {
      await h.projects.remove('prj_1');

      final offer = await offered();

      expect(offer.repository, isNull);
    });

    test(
      'names the version commit of the job the checkout starts from',
      () async {
        final prepare = await h.job(
          steps: [
            const StepPlan(kind: 'version.bump', input: {}, sideEffect: true),
          ],
        );
        final bump = (await h.steps(prepare)).single;
        await h.jobs.jobs.updateStep(
          bump.copyWith(
            state: StepState.succeeded,
            result: {'commit': 'b' * 40},
          ),
        );

        final offer = await offered(
          steps: [
            StepPlan(
              kind: 'git.checkout',
              input: {
                'worktree': const <String, dynamic>{},
                'commitFromJob': prepare,
              },
              sideEffect: false,
            ),
          ],
        );

        expect(offer.sha, 'b' * 40);
      },
    );

    test('names no commit when the job it starts from made none', () async {
      final prepare = await h.job(steps: [h.script()]);

      final offer = await offered(
        steps: [
          StepPlan(
            kind: 'git.checkout',
            input: {
              'worktree': const <String, dynamic>{},
              'commitFromJob': prepare,
            },
            sideEffect: false,
          ),
        ],
      );

      expect(offer.sha, isNull);
    });
  });
}
