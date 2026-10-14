import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/notify_harness.dart';

void main() {
  late NotifyHarness h;
  late Notifier notifier;

  const failed = JobStateChanged(
    jobId: 'job_1',
    projectId: 'prj_1',
    state: JobState.failed,
  );

  setUp(() async {
    h = await NotifyHarness.create();
    await h.runs.create(runRecord());
    await h.jobs.create(jobRecord(runId: 'run_1', message: 'boom'), const []);
    notifier = h.notifier()..start();
  });

  tearDown(() => notifier.stop());

  group('what it tells', () {
    test(
      'a production failure: an event for the app and a Slack post',
      () async {
        await h.addSlack();

        h.events.append(failed);
        await h.settle();

        final raised = await h.raised();
        expect(raised.single.kind, NotificationKind.jobFailed);
        expect(raised.single.title, 'Production job failed');
        expect(raised.single.jobId, 'job_1');
        expect(h.webhook.posts, [
          (
            Uri.parse('https://hooks.slack.com/services/T0/B0/XYZ'),
            '*Production job failed*\nocto/demo: Build iOS - boom',
          ),
        ]);
      },
    );

    test('only the app is told when the project has no webhook', () async {
      h.events.append(failed);
      await h.settle();

      expect((await h.raised()).single.kind, NotificationKind.jobFailed);
      expect(h.webhook.attempts, 0);
    });

    test('a webhook that a check rejected is not used', () async {
      await h.addSlack(status: CredentialStatus.rejected);

      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(1));
      expect(h.webhook.attempts, 0);
    });

    test('a credential of another kind is not a webhook', () async {
      await h.credentials.save(
        CredentialRecord(
          id: 'crd_gh',
          flavor: demoFlavorOf('prod'),
          kind: CredentialKind.github,
          secretKey: 'credential.prod.github',
        ),
      );
      await h.secrets.write('credential.prod.github', 'ghp_x');

      h.events.append(failed);
      await h.settle();

      expect(h.webhook.attempts, 0);
    });

    test('a webhook whose secret is gone is skipped', () async {
      final record = await h.addSlack();
      h.secrets.values.remove(record.secretKey);

      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(1));
      expect(h.webhook.attempts, 0);
      expect(h.errors, isEmpty);
    });

    test('events that are not worth telling are not', () async {
      await h.addSlack();

      h.events
        ..append(const EngineStarted(version: '1', apiVersion: '1'))
        ..append(
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.running,
          ),
        );
      await h.settle();

      expect(await h.raised(), isEmpty);
      expect(h.webhook.attempts, 0);
    });

    test('its own notifications do not start another', () async {
      await h.addSlack();

      h.events.append(failed);
      await h.settle();
      await h.settle();

      expect(await h.raised(), hasLength(1));
      expect(h.webhook.posts, hasLength(1));
    });

    test('locked secrets go to the app only', () async {
      await h.addSlack();

      h.secrets.announce(SecretsStatus.locked);
      await h.settle();

      final raised = await h.raised();
      expect(raised.single.kind, NotificationKind.secretsLocked);
      expect(raised.single.projectId, isNull);
      expect(h.webhook.attempts, 0);
    });

    test('secrets that unlock are nothing to tell', () async {
      h.secrets.announce(SecretsStatus.unlocked);
      await h.settle();

      expect(await h.raised(), isEmpty);
    });

    test(
      'a webhook that cannot be read because of the lock is quiet',
      () async {
        await h.addSlack();
        h.secrets.failure = const SecretsLockedException('locked');

        h.events.append(failed);
        await h.settle();

        expect(await h.raised(), hasLength(1));
        expect(h.webhook.attempts, 0);
        expect(h.errors, isEmpty);
      },
    );
  });

  group('flapping', () {
    test('the same notice within the window is told once', () async {
      await h.addSlack();

      h.events
        ..append(failed)
        ..append(failed);
      await h.settle();
      h.clock.advance(const Duration(minutes: 14));
      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(1));
      expect(h.webhook.posts, hasLength(1));
    });

    test('and again once the window has passed', () async {
      await h.addSlack();

      h.events.append(failed);
      await h.settle();
      h.clock.advance(const Duration(minutes: 15));
      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(2));
      expect(h.webhook.posts, hasLength(2));
    });

    test('different notices do not hide each other', () async {
      await h.jobs.create(
        jobRecord(id: 'job_2', runId: 'run_1', name: 'Build Android'),
        const [],
      );

      h.events
        ..append(failed)
        ..append(
          const JobStateChanged(
            jobId: 'job_2',
            projectId: 'prj_1',
            state: JobState.failed,
          ),
        );
      await h.settle();

      expect(await h.raised(), hasLength(2));
    });

    test('at most so many messages go to Slack in a minute', () async {
      await notifier.stop();
      notifier = h.notifier(slackPerMinute: 2)..start();
      await h.addSlack();
      for (final id in ['job_2', 'job_3', 'job_4']) {
        await h.jobs.create(jobRecord(id: id, runId: 'run_1'), const []);
      }

      for (final id in ['job_1', 'job_2', 'job_3']) {
        h.events.append(
          JobStateChanged(
            jobId: id,
            projectId: 'prj_1',
            state: JobState.failed,
          ),
        );
      }
      await h.settle();

      // The app hears of all three; Slack of two.
      expect(await h.raised(), hasLength(3));
      expect(h.webhook.posts, hasLength(2));

      h.clock.advance(const Duration(minutes: 1));
      h.events.append(
        const JobStateChanged(
          jobId: 'job_4',
          projectId: 'prj_1',
          state: JobState.failed,
        ),
      );
      await h.settle();

      expect(h.webhook.posts, hasLength(3));
    });
  });

  group('Slack trouble', () {
    test('a failing message is tried again, then goes through', () async {
      await h.addSlack();
      h.webhook.failures.addAll(const [
        SlackDeliveryException('503', retryable: true),
        SlackDeliveryException('503', retryable: true),
      ]);

      h.events.append(failed);
      await h.settle();

      expect(h.webhook.posts, hasLength(1));
      expect(h.sleeps, [
        const Duration(seconds: 1),
        const Duration(seconds: 5),
      ]);
      expect(h.errors, isEmpty);
    });

    test(
      'one that never goes through is reported and the next still does',
      () async {
        await h.addSlack();
        h.webhook.failures.add(const SlackDeliveryException('404'));
        await h.jobs.create(jobRecord(id: 'job_2', runId: 'run_1'), const []);

        h.events
          ..append(failed)
          ..append(
            const JobStateChanged(
              jobId: 'job_2',
              projectId: 'prj_1',
              state: JobState.failed,
            ),
          );
        await h.settle();

        expect(h.errors.single, isA<SlackDeliveryException>());
        expect(h.webhook.posts, hasLength(1));
        expect(await h.raised(), hasLength(2));
      },
    );

    test('a failure in reading the repositories is reported', () async {
      await h.jobs.create(jobRecord(id: 'job_x', runId: 'run_1'), const []);
      await notifier.stop();
      final broken = Notifier(
        events: h.events,
        factory: NoticeFactory(
          projects: h.projects,
          releases: h.releases,
          jobs: _ThrowingJobs(),
          runs: h.runs,
          masker: const NoMasking(),
        ),
        credentials: h.credentials,
        secrets: h.secrets,
        slack: SlackSender(webhook: h.webhook),
        clock: h.clock,
        onError: (error, _) => h.errors.add(error),
      )..start();

      h.events
        ..append(failed)
        ..append(const ProjectRemoved(projectId: 'prj_1'));
      await h.settle();
      await broken.stop();

      expect(h.errors.single, isA<StateError>());
    });

    test('messages of one project go out in the order of the events', () async {
      await h.addSlack();
      final order = <String>[];
      final slow = _SlowWebhook(order);
      await notifier.stop();
      final ordered = Notifier(
        events: h.events,
        factory: h.factory,
        credentials: h.credentials,
        secrets: h.secrets,
        slack: SlackSender(webhook: slow),
        clock: h.clock,
      )..start();
      await h.jobs.create(jobRecord(id: 'job_2', runId: 'run_1'), const []);

      h.events
        ..append(failed)
        ..append(
          const JobStateChanged(
            jobId: 'job_2',
            projectId: 'prj_1',
            state: JobState.failed,
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ordered.stop();

      expect(order, ['start', 'end', 'start', 'end']);
    });
  });

  group('lifecycle', () {
    test('starting twice listens once', () async {
      notifier.start();
      expect(notifier.isRunning, isTrue);

      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(1));
    });

    test('after stop it hears nothing', () async {
      await notifier.stop();

      expect(notifier.isRunning, isFalse);
      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), isEmpty);
    });

    test('stop drops a message that waits to be tried again', () async {
      await h.addSlack();
      h.webhook.failures.add(
        const SlackDeliveryException('503', retryable: true),
      );
      final waiting = Completer<void>();
      final release = Completer<void>();
      await notifier.stop();
      final stopping = Notifier(
        events: h.events,
        factory: h.factory,
        credentials: h.credentials,
        secrets: h.secrets,
        slack: SlackSender(
          webhook: h.webhook,
          sleep: (wait) async {
            waiting.complete();
            await release.future;
          },
        ),
        clock: h.clock,
        onError: (error, _) => h.errors.add(error),
      )..start();

      h.events.append(failed);
      await waiting.future;
      final stopped = stopping.stop();
      release.complete();
      await stopped;

      expect(h.webhook.attempts, 1);
      expect(h.webhook.posts, isEmpty);
      expect(h.errors.single, isA<SlackDeliveryException>());
    });

    test('it can be started again after a stop', () async {
      await notifier.stop();
      notifier.start();

      h.events.append(failed);
      await h.settle();

      expect(await h.raised(), hasLength(1));
    });
  });
}

CredentialFlavor demoFlavorOf(String name) => CredentialFlavor(
  id: 'flv_$name',
  projectId: 'prj_1',
  appPath: '.',
  name: name,
);

class _ThrowingJobs extends InMemoryJobRepository {
  @override
  Future<JobRecord?> get(String id) async => throw StateError('disk on fire');
}

class _SlowWebhook implements SlackWebhook {
  new(this.order);

  final List<String> order;

  @override
  Future<void> post(Uri url, String text) async {
    order.add('start');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    order.add('end');
  }
}
