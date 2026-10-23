import 'dart:async';
import 'dart:convert';

import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/runner_socket.dart';
import 'package:xp_api/xp_api.dart';

/// The connection of a runner, played by the test: the test is the engine.
class FakeRunnerSocket implements RunnerSocket {
  final _incoming = StreamController<String>();

  /// The frames the runner sent, as JSON.
  final sent = <Map<String, dynamic>>[];

  /// Set to make [send] throw, as a socket does that is gone.
  bool sendFails = false;

  @override
  int? closeCode;

  /// Whether the runner closed the connection.
  bool closedByRunner = false;

  @override
  Stream<String> get frames => _incoming.stream;

  @override
  void send(String text) {
    if (sendFails) throw StateError('The connection is gone.');
    sent.add(jsonDecode(text) as Map<String, dynamic>);
  }

  @override
  Future<void> close(int code, String reason) async {
    closedByRunner = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// The frames of type [T] the runner sent so far.
  List<T> sentOf<T extends RunnerFrame>() =>
      [for (final json in sent) RunnerFrame.fromJson(json)]
          .whereType<T>()
          .toList();

  /// The engine sends [frame].
  void engine(EngineFrame frame) => _incoming.add(jsonEncode(frame.toJson()));

  /// The engine sends the raw [text].
  void engineText(String text) => _incoming.add(text);

  /// The engine ends the connection with [code].
  Future<void> engineCloses([int? code]) async {
    closeCode = code;
    await _incoming.close();
  }

  /// The connection breaks with an error.
  void breaks() => _incoming.addError(StateError('reset by peer'));
}

/// The job of a lease, played by the test.
class FakeLeaseWork implements LeaseWork {
  /// Creates the work for [offer] and its [outbox].
  new(this.offer, this.outbox);

  /// The lease.
  final LeaseOfferFrame offer;

  /// Where the job reports.
  final LeaseOutbox outbox;

  final _finished = Completer<void>();

  /// Whether the runner cancelled the job.
  bool cancelled = false;

  @override
  Future<void> get finished => _finished.future;

  /// The job ends: its steps are done.
  void finish() {
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    outbox.abandon();
    finish();
  }
}

/// A lease offer for the job [jobId] with steps of [kinds].
LeaseOfferFrame offerOf(
  String jobId, {
  String leaseId = 'lse_1',
  List<String> kinds = const ['command'],
  List<String> capabilities = const [],
  List<String> secrets = const [],
  String? sha,
  LeaseRepository? repository,
}) => LeaseOfferFrame(
  leaseId: leaseId,
  jobId: jobId,
  projectId: 'prj_1',
  sha: sha ?? 'a' * 40,
  name: 'Job $jobId',
  repository:
      repository ??
      const LeaseRepository(
        cacheKey: '7',
        githubRepoId: 7,
        sshUrl: 'git@github.com:owner/app.git',
      ),
  stage: 0,
  capabilities: capabilities,
  expiresAt: DateTime.utc(2026, 10, 14, 12),
  steps: [
    for (final (ordinal, kind) in kinds.indexed)
      LeaseStep(
        ordinal: ordinal,
        kind: kind,
        sideEffect: false,
        state: StepState.pending,
        attempts: 0,
        input: const {},
      ),
  ],
  secrets: secrets,
);
