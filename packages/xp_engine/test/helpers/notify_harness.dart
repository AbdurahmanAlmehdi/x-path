import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'credential_harness.dart';
import 'workflow_fixtures.dart';

/// A secret store whose status the test switches.
class SwitchableSecretStore extends BytesSecretStore {
  final _changes = StreamController<SecretsStatus>.broadcast();

  @override
  Stream<SecretsStatus> get statusChanges => _changes.stream;

  /// Announces [status].
  void announce(SecretsStatus status) => _changes.add(status);
}

/// A release of the demo project for tests.
ReleaseRecord releaseRecord({
  String id = 'rel_1',
  String projectId = 'prj_1',
  String flavor = 'prod',
  String version = '1.2.0',
  int build = 5,
  ReleaseState state = ReleaseState.live,
  Map<ReleaseStore, StoreEntry> stores = const {},
  List<ReleaseBuild> builds = const [],
  String? tag,
  String? headSha,
  String? mergeRunId,
  String? message,
}) => ReleaseRecord(
  id: id,
  projectId: projectId,
  appPath: '.',
  flavor: flavor,
  version: version,
  build: build,
  state: state,
  stores: stores,
  builds: builds,
  baseBranch: 'main',
  createdAt: DateTime.utc(2026, 10, 14, 8),
  updatedAt: DateTime.utc(2026, 10, 14, 8),
  tag: tag,
  headSha: headSha,
  mergeRunId: mergeRunId,
  message: message,
);

/// A job of the demo project for tests.
JobRecord jobRecord({
  String id = 'job_1',
  JobState state = JobState.failed,
  String? runId,
  String? releaseId,
  String? name = 'Build iOS',
  String? message,
  DateTime? createdAt,
  DateTime? finishedAt,
}) => JobRecord(
  id: id,
  workflowVersionId: 'wfv_1',
  projectId: 'prj_1',
  state: state,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 14, 8),
  finishedAt: finishedAt,
  runId: runId,
  releaseId: releaseId,
  name: name,
  message: message,
);

/// A run of the demo project that holds the project lock, or does not.
RunRecord runRecord({String id = 'run_1', bool locksProject = true}) =>
    RunRecord(
      id: id,
      projectId: 'prj_1',
      workflowId: 'wf_1',
      workflowVersionId: 'wfv_1',
      sha: 'a' * 40,
      locksProject: locksProject,
      createdAt: DateTime.utc(2026, 10, 14, 8),
    );

/// The repositories a [Notifier] reads, with the demo project in them.
class NotifyHarness {
  new _();

  /// Creates the harness.
  static Future<NotifyHarness> create() async {
    final harness = NotifyHarness._();
    await harness.projects.add(demoProject());
    return harness;
  }

  /// The time.
  final clock = ManualClock(DateTime.utc(2026, 10, 14, 9));

  /// The event log.
  late final events = InMemoryEventLog(clock: clock);

  /// The projects.
  final projects = InMemoryProjectRepository();

  /// The releases.
  final releases = InMemoryReleaseRepository();

  /// The jobs.
  final jobs = InMemoryJobRepository();

  /// The runs.
  final runs = InMemoryRunRepository();

  /// The credentials.
  final credentials = InMemoryCredentialRepository([
    demoFlavor('prod'),
    demoFlavor('dev'),
  ]);

  /// The secrets.
  final secrets = SwitchableSecretStore();

  /// What reached Slack.
  final webhook = FakeSlackWebhook();

  /// The waits of the Slack sender.
  final sleeps = <Duration>[];

  /// Failures that were reported.
  final errors = <Object>[];

  /// The masker the factory uses.
  final masker = _ListMasker();

  late final factory = NoticeFactory(
    projects: projects,
    releases: releases,
    jobs: jobs,
    runs: runs,
    masker: masker,
  );

  /// Saves a Slack credential for [flavor] whose webhook is [url].
  Future<CredentialRecord> addSlack({
    String flavor = 'prod',
    String url = 'https://hooks.slack.com/services/T0/B0/XYZ',
    CredentialStatus status = CredentialStatus.verified,
  }) async {
    final record = CredentialRecord(
      id: 'crd_${flavor}_slack',
      flavor: demoFlavor(flavor),
      kind: CredentialKind.slack,
      secretKey: 'credential.$flavor.slack',
      status: status,
    );
    await credentials.save(record);
    await secrets.write(record.secretKey, url);
    return record;
  }

  /// A notifier over the harness.
  Notifier notifier({
    Duration dedupeWindow = const Duration(minutes: 15),
    int slackPerMinute = 20,
  }) => Notifier(
    events: events,
    factory: factory,
    credentials: credentials,
    secrets: secrets,
    slack: SlackSender(
      webhook: webhook,
      sleep: (wait) async => sleeps.add(wait),
    ),
    clock: clock,
    dedupeWindow: dedupeWindow,
    slackPerMinute: slackPerMinute,
    onError: (error, _) => errors.add(error),
  );

  /// The notifications logged so far.
  Future<List<NotificationRaised>> raised() async {
    final seen = <NotificationRaised>[];
    final subscription = events.subscribe(after: 0).listen((entry) {
      if (entry.event case final NotificationRaised event) seen.add(event);
    });
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }

  /// Lets what the notifier does asynchronously finish.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// A masker that hides the secrets it was given.
class _ListMasker implements OutputMasker {
  final _secrets = <String>[];

  @override
  void add(String secret) => _secrets.add(secret);

  @override
  StreamMasker newStream() => _ListStream(_secrets);
}

class _ListStream implements StreamMasker {
  new(this._secrets);

  final List<String> _secrets;

  @override
  String add(String piece) {
    var masked = piece;
    for (final secret in _secrets) {
      masked = masked.replaceAll(secret, '***');
    }
    return masked;
  }

  @override
  String flush() => '';
}
