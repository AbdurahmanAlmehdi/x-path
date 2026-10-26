import 'dart:async';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/releases/release_exceptions.dart';
import 'package:xp_engine/src/releases/release_opener.dart';
import 'package:xp_engine/src/releases/release_progress.dart';
import 'package:xp_engine/src/releases/release_record.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/releases/release_state_machine.dart';
import 'package:xp_engine/src/releases/release_status.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';
import 'package:xp_engine/src/scheduler/run_service.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/upload/upload_app_store_input.dart';
import 'package:xp_engine/src/steps/upload/upload_play_input.dart';
import 'package:xp_engine/src/tokens/device_token.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/workflows/workflow_service.dart';

/// Dispatches the workflow [workflowId] of the project: the
/// `WorkflowDispatcher.dispatch` the service starts new builds and merges
/// with. It is a function so that the dispatcher, which tells the service
/// about the releases it makes, and the service do not need each other at
/// construction.
typedef DispatchWorkflow = Future<Run> Function(
  String projectId,
  String workflowId,
  DispatchRequest request,
);

/// The built-in workflow that merges the pull request of a release.
const releaseMergeWorkflow = 'release-merge';

/// The built-in workflow that changes the rollout of a release (U7a).
const releaseRolloutWorkflow = 'release-rollout';

/// The built-in workflow that promotes or rolls back a Shorebird patch of a
/// release (U7b).
const shorebirdTrackWorkflow = 'shorebird-track';

/// The states of a release whose store rollouts can change: the stores
/// approved it, or it is out.
const Set<ReleaseState> _rolledOut = {
  ReleaseState.approved,
  ReleaseState.live,
  ReleaseState.merged,
};

/// The states in which the stores still decide where a release goes.
const Set<ReleaseState> _waitingOnStores = {
  ReleaseState.uploaded,
  ReleaseState.inReview,
  ReleaseState.approved,
};

/// The store states that a store can still move on from, by polling or by
/// hand.
const Set<StoreState> _pollable = {
  StoreState.uploaded,
  StoreState.inReview,
  StoreState.approved,
};

/// The releases (D-17): their state machine, driven by what the jobs did and
/// what the stores say, and the actions the owner takes on them.
///
/// **Where a release comes from.** A dispatch of a workflow that cuts a release
/// branch makes one `draft` release per flavor ([open]); a new build after a
/// rejection and the merge of the pull request are runs that [attach] to an
/// existing one. Every job of such a run names its release.
///
/// **How it moves.** [sync] reads the steps of the jobs of the current build:
/// `building` once a build step started, `uploaded` once every store the
/// release targets has its upload, and the branch, tag and pull request are
/// recorded as their steps succeed. The stores then decide: [pollDue] and
/// [refresh] ask them (App Store Connect, the iTunes lookup, Play), and
/// [setStoreStatus] takes the owner's word for a store the engine cannot
/// read. The state of the release follows from the status in each store:
/// `rejected` if any store rejected, else the least advanced of them
/// (`in_review` while either store reviews, `live` only when every store is).
/// A merge run that merged the pull request makes it `merged`.
///
/// **Safety.** A status only moves forward, and a store that cannot be read
/// keeps its status. Setting a status by hand, which moves a release toward
/// the merge of its pull request, and abandoning are for `app` and `cli`
/// tokens (D-13). A new build and the merge are workflows with gates, so any
/// token may ask for them and none but an `app` or `cli` token can approve.
class ReleaseService implements ReleaseOpener {
  /// Creates the service.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._releases,
    required this._jobs,
    required this._runRecords,
    required this._runs,
    required this._workflows,
    required this._poller,
    required this._events,
    required this._clock,
    required this._dispatch,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ReleaseRepository _releases;
  final JobRepository _jobs;
  final RunRepository _runRecords;
  final RunService _runs;
  final WorkflowService _workflows;
  final ReleaseStatusPoller _poller;
  final EventLog _events;
  final Clock _clock;
  final DispatchWorkflow _dispatch;
  final Random _random;
  final _tails = <String, Future<void>>{};

  // -------------------------------------------------------------- opening

  @override
  Future<Map<String, String>> open(ReleaseOpening opening) async {
    final ids = <String, String>{};
    for (final flavor in opening.flavors) {
      for (final old in await _releases.list(
        projectId: opening.projectId,
        appPath: opening.appPath,
        states: {ReleaseState.draft, ReleaseState.building},
      )) {
        if (old.flavor == flavor.flavor && old.version == opening.version) {
          await _abandonUnlessStarted(old.id, opening.version);
        }
      }
      final now = _clock.now();
      final release = ReleaseRecord(
        id: _newId(),
        projectId: opening.projectId,
        appPath: opening.appPath,
        flavor: flavor.flavor,
        version: opening.version,
        build: opening.build,
        state: ReleaseState.draft,
        stores: _targets(flavor.steps, opening.storeCountry, now),
        builds: [
          ReleaseBuild(
            build: opening.build,
            runId: opening.runId,
            createdAt: now,
          ),
        ],
        baseBranch: opening.baseBranch,
        createdAt: now,
        updatedAt: now,
      );
      await _releases.create(release);
      await _releases.addEvent(
        release.id,
        ReleaseEvent(
          kind: ReleaseEventKind.created,
          at: now,
          detail: '${release.version}+${release.build}',
          runId: opening.runId,
        ),
      );
      _events.append(
        ReleaseCreated(
          releaseId: release.id,
          projectId: release.projectId,
          flavor: release.flavor,
          version: release.version,
          build: release.build,
        ),
      );
      ids[flavor.flavor] = release.id;
    }
    return ids;
  }

  /// The stores the steps upload to, each `pending` until its upload is done.
  Map<ReleaseStore, StoreEntry> _targets(
    List<StepPlan> steps,
    String country,
    DateTime now,
  ) {
    final stores = <ReleaseStore, StoreEntry>{};
    for (final step in steps) {
      switch (step.kind) {
        case 'upload.appStore':
          final input = UploadAppStoreInput.fromJson(step.input);
          stores[ReleaseStore.apple] = StoreEntry(
            store: ReleaseStore.apple,
            state: StoreState.pending,
            source: StatusSource.upload,
            identity: {
              'bundleId': input.bundleId,
              'appleAppId': input.appleAppId,
              'country': country,
            },
            changedAt: now,
          );
        case 'upload.play':
          final input = UploadPlayInput.fromJson(step.input);
          stores[ReleaseStore.play] = StoreEntry(
            store: ReleaseStore.play,
            state: StoreState.pending,
            source: StatusSource.upload,
            identity: {'packageName': input.packageName, 'track': input.track},
            changedAt: now,
          );
      }
    }
    return stores;
  }

  Future<void> _abandonUnlessStarted(String id, String version) =>
      _locked(id, () async {
        final release = await _require(id);
        // It may have moved on since the list was read.
        if (release.state != ReleaseState.draft &&
            release.state != ReleaseState.building) {
          return;
        }
        await _save(
          release,
          _move(
            release.copyWith(message: 'Replaced by a new release of $version.'),
            ReleaseState.abandoned,
          ),
        );
      });

  @override
  Future<void> attach({
    required String releaseId,
    required String projectId,
    required ReleaseRunKind kind,
    required String runId,
    int? build,
  }) => _locked(releaseId, () async {
    final release = await _require(releaseId);
    if (release.projectId != projectId) {
      throw ReleaseNotFoundException(releaseId);
    }
    final now = _clock.now();
    switch (kind) {
      case ReleaseRunKind.build:
        if (release.state != ReleaseState.rejected) {
          throw ReleaseStateException(
            'Only a rejected release gets a new build; ${release.id} is '
            '${release.state.wire}.',
          );
        }
        final next = release.copyWith(
          build: build,
          stores: {
            for (final entry in release.stores.entries)
              entry.key: entry.value.copyWith(
                state: StoreState.pending,
                source: StatusSource.upload,
                // The store still reports the rejection of the earlier build
                // until the new one is submitted.
                ignored: entry.value.state == StoreState.rejected
                    ? entry.value.detail
                    : null,
                detail: null,
                checkedAt: null,
                changedAt: now,
                note: null,
              ),
          },
          builds: [
            ...release.builds,
            ReleaseBuild(build: build!, runId: runId, createdAt: now),
          ],
          tag: null,
          headSha: null,
          message: null,
        );
        await _save(
          release,
          _move(next, ReleaseState.building),
          storeEvents: true,
        );
        await _releases.addEvent(
          release.id,
          ReleaseEvent(
            kind: ReleaseEventKind.build,
            at: now,
            detail: '$build',
            runId: runId,
          ),
        );
      case ReleaseRunKind.merge:
        if (release.state != ReleaseState.live ||
            release.prNumber == null ||
            release.mergeRunId != null) {
          throw ReleaseStateException(
            'The pull request of ${release.id} cannot be merged now: the '
            'release is ${release.state.wire}, its pull request is '
            '${release.prNumber ?? 'not opened'} and the run that merges it '
            'is ${release.mergeRunId ?? 'not started'}.',
          );
        }
        await _save(release, release.copyWith(mergeRunId: runId));
        await _releases.addEvent(
          release.id,
          ReleaseEvent(
            kind: ReleaseEventKind.mergeRequested,
            at: now,
            runId: runId,
          ),
        );
      case ReleaseRunKind.rollout:
        if (!_rolledOut.contains(release.state)) {
          throw ReleaseStateException(
            'The rollout of ${release.id} cannot change: it is '
            '${release.state.wire}.',
          );
        }
        await _releases.addEvent(
          release.id,
          ReleaseEvent(
            kind: ReleaseEventKind.rolloutRequested,
            at: now,
            runId: runId,
          ),
        );
      case ReleaseRunKind.patch:
        if (!_rolledOut.contains(release.state)) {
          throw ReleaseStateException(
            'A patch of ${release.id} cannot change: it is '
            '${release.state.wire}. Patches apply once the stores approved '
            'the release.',
          );
        }
    }
  });

  @override
  Future<String?> patchable({
    required String projectId,
    required String appPath,
    required String flavor,
    required AppVersion version,
  }) async {
    for (final release in await _releases.list(
      projectId: projectId,
      appPath: appPath,
      states: _rolledOut,
    )) {
      if (release.flavor == flavor &&
          release.version == '${version.name}' &&
          release.build == version.build) {
        return release.id;
      }
    }
    return null;
  }

  // -------------------------------------------------------------- reading

  /// The releases, newest first; only those of [projectId], of the app at
  /// [appPath] and in [state] if given. Each is brought up to date with its
  /// jobs first.
  Future<List<Release>> list({
    String? projectId,
    String? appPath,
    ReleaseState? state,
  }) async {
    final records = await _releases.list(
      projectId: projectId,
      appPath: appPath,
    );
    final releases = <Release>[];
    for (final record in records) {
      final current = await sync(record.id);
      if (state == null || current.state == state) {
        releases.add(current.toApi());
      }
    }
    return releases;
  }

  /// The release [id], brought up to date with its jobs.
  ///
  /// Throws a [ReleaseNotFoundException] if there is none.
  Future<Release> get(String id) async => (await sync(id)).toApi();

  // --------------------------------------------------------------- syncing

  /// Brings the release [id] up to date with its jobs, and returns it. A
  /// release that is over stays as it is.
  ///
  /// Throws a [ReleaseNotFoundException] if there is none.
  Future<ReleaseRecord> sync(String id) => _locked(id, () => _sync(id));

  /// Brings up to date the release the job [jobId] belongs to, if it belongs
  /// to one. The `ReleaseWatcher` calls it when a job or step changes.
  Future<void> syncJob(String jobId) async {
    final job = await _jobs.get(jobId);
    final releaseId = job?.releaseId;
    if (releaseId == null) return;
    await sync(releaseId);
    if (job!.state == JobState.succeeded) {
      await _locked(releaseId, () => _recordOutcomes(releaseId, job));
    }
  }

  /// Adds to the history of the release [releaseId] what the steps of the
  /// finished [job] did to it in the stores and in Shorebird, once each.
  Future<void> _recordOutcomes(String releaseId, JobRecord job) async {
    final known = await _releases.events(releaseId);
    final at = job.finishedAt ?? _clock.now();
    for (final step in await _jobs.steps(job.id)) {
      if (step.state != StepState.succeeded) continue;
      final event = _outcomeOf(step, job.runId, at);
      if (event == null || known.any((old) => _sameOutcome(old, event))) {
        continue;
      }
      await _releases.addEvent(releaseId, event);
    }
  }

  /// What the succeeded [step] did to a release, if anything worth its
  /// history.
  static ReleaseEvent? _outcomeOf(StepRecord step, String? runId, DateTime at) {
    switch (step.kind) {
      case 'store.rollout':
        final result = step.result ?? const <String, dynamic>{};
        final fraction = result['userFraction'] as num?;
        return ReleaseEvent(
          kind: ReleaseEventKind.rollout,
          at: at,
          store: ReleaseStore.values
              .where((store) => store.wire == result['store'])
              .firstOrNull,
          detail: [
            ?result['state'] as String?,
            if (fraction != null) '${(fraction * 100).round()} %',
          ].join(' · '),
          runId: runId,
        );
      case 'shorebird.patch':
        return ReleaseEvent(
          kind: ReleaseEventKind.patch,
          at: at,
          detail: step.input['platform'] as String?,
          runId: runId,
          patchNumber: step.input['patchNumber'] as int?,
        );
      case 'shorebird.track':
        return ReleaseEvent(
          kind: step.input['action'] == PatchAction.rollback.wire
              ? ReleaseEventKind.patchRolledBack
              : ReleaseEventKind.patchPromoted,
          at: at,
          runId: runId,
          patchNumber: step.input['patchNumber'] as int?,
        );
    }
    return null;
  }

  static bool _sameOutcome(ReleaseEvent a, ReleaseEvent b) =>
      a.kind == b.kind &&
      a.runId == b.runId &&
      a.store == b.store &&
      a.detail == b.detail &&
      a.patchNumber == b.patchNumber;

  Future<ReleaseRecord> _sync(String id) async {
    final start = await _require(id);
    if (start.state.isTerminal) return start;
    var release = start;
    final progress = BuildProgress.of(await _progressOf(release));
    release = release.copyWith(
      branch: progress.branch ?? release.branch,
      tag: progress.tag ?? release.tag,
      headSha: progress.headSha ?? release.headSha,
      prNumber: progress.prNumber ?? release.prNumber,
      prUrl: progress.prUrl ?? release.prUrl,
    );
    final now = _clock.now();
    final events = <EngineEvent>[];
    release = release.copyWith(
      stores: {
        for (final entry in release.stores.entries)
          entry.key:
              progress.uploaded.contains(entry.key) &&
                  entry.value.state == StoreState.pending
              ? _storeChanged(
                  release,
                  entry.value.copyWith(
                    state: StoreState.uploaded,
                    source: StatusSource.upload,
                    changedAt: now,
                  ),
                  events,
                )
              : entry.value,
      },
    );
    final isBuilding =
        release.state == ReleaseState.draft ||
        release.state == ReleaseState.building;
    if (isBuilding) {
      release = release.copyWith(message: progress.failure);
    }
    if (release.state == ReleaseState.draft &&
        (progress.buildStarted || progress.uploaded.isNotEmpty)) {
      release = _move(release, ReleaseState.building, events);
    }
    release = await _merged(release, events);
    release = _advance(release, events);
    return await _persist(start, release, events);
  }

  /// Looks at the run that merges the pull request: it merged it, or it ended
  /// without, and the merge can be requested again.
  Future<ReleaseRecord> _merged(
    ReleaseRecord release,
    List<EngineEvent> events,
  ) async {
    final runId = release.mergeRunId;
    if (runId == null) return release;
    final merge = MergeProgress.of(await _progressOf(release, runId: runId));
    if (merge.mergeCommit != null) {
      return _move(
        release.copyWith(mergeCommit: merge.mergeCommit),
        ReleaseState.merged,
        events,
      );
    }
    if (merge.ended) {
      return release.copyWith(
        mergeRunId: null,
        message: 'The merge run $runId ended: ${merge.failure}',
      );
    }
    return release;
  }

  Future<List<JobProgress>> _progressOf(
    ReleaseRecord release, {
    String? runId,
  }) async => [
    for (final job in await _jobs.forRun(runId ?? release.runId))
      if (job.releaseId == release.id)
        JobProgress(job, await _jobs.steps(job.id)),
  ];

  /// Moves the release to the state its stores add up to, when that is a
  /// move the state machine allows.
  ReleaseRecord _advance(ReleaseRecord release, List<EngineEvent> events) {
    final derived = _derive(release.stores.values);
    if (derived == null ||
        derived == release.state ||
        !ReleaseStateMachine.canMove(release.state, derived)) {
      return release;
    }
    return _move(release, derived, events);
  }

  /// The state the status in each store adds up to: `rejected` if any store
  /// rejected, else the least advanced; `null` while a store has no build
  /// yet (or the release targets none).
  static ReleaseState? _derive(Iterable<StoreEntry> stores) {
    if (stores.isEmpty || stores.any((e) => e.state == StoreState.pending)) {
      return null;
    }
    if (stores.any((entry) => entry.state == StoreState.rejected)) {
      return ReleaseState.rejected;
    }
    final order = [
      StoreState.uploaded,
      StoreState.inReview,
      StoreState.approved,
      StoreState.live,
    ];
    final least = stores
        .map((entry) => order.indexOf(entry.state))
        .reduce((a, b) => a < b ? a : b);
    return switch (order[least]) {
      StoreState.uploaded => ReleaseState.uploaded,
      StoreState.inReview => ReleaseState.inReview,
      StoreState.approved => ReleaseState.approved,
      _ => ReleaseState.live,
    };
  }

  // --------------------------------------------------------------- polling

  /// Asks the stores about the release [id] now, whatever was asked before
  /// (the manual refresh). Returns the release as it stands.
  ///
  /// Throws a [ReleaseNotFoundException] if there is none.
  Future<Release> refresh(String id) async =>
      (await _locked(id, () => _poll(id, force: true))).release.toApi();

  /// Asks the stores about every release that waits for them and has not
  /// been asked within ten minutes. Returns how many stores were asked.
  Future<int> pollDue() async {
    var asked = 0;
    final waiting = await _releases.list(states: _waitingOnStores);
    for (final release in waiting) {
      asked += (await _locked(
        release.id,
        () => _poll(release.id, force: false),
      )).asked;
    }
    return asked;
  }

  Future<({ReleaseRecord release, int asked})> _poll(
    String id, {
    required bool force,
  }) async {
    final synced = await _sync(id);
    if (!_waitingOnStores.contains(synced.state)) {
      return (release: synced, asked: 0);
    }
    var release = synced;
    var asked = 0;
    final events = <EngineEvent>[];
    for (final entry in synced.stores.values) {
      if (!_pollable.contains(entry.state) ||
          !(force || _poller.isDue(entry))) {
        continue;
      }
      asked++;
      final poll = await _poller.poll(release, entry);
      release = release.copyWith(
        stores: {
          ...release.stores,
          entry.store: _applied(release, entry, poll, events),
        },
      );
    }
    release = _advance(release, events);
    return (release: await _persist(synced, release, events), asked: asked);
  }

  /// [entry] after the store said [poll].
  StoreEntry _applied(
    ReleaseRecord release,
    StoreEntry entry,
    StorePoll poll,
    List<EngineEvent> events,
  ) {
    final now = _clock.now();
    final reading = poll.reading;
    if (reading == null) {
      return entry.copyWith(checkedAt: now, note: poll.note);
    }
    final checked = entry.copyWith(
      checkedAt: now,
      note: null,
      detail: reading.detail,
    );
    final state = reading.state;
    if (state == null || reading.detail == entry.ignored) return checked;
    if (!_canAdvance(entry.state, state)) return checked;
    return _storeChanged(
      release,
      checked.copyWith(
        state: state,
        source: reading.source,
        changedAt: now,
        ignored: null,
      ),
      events,
    );
  }

  /// Whether the status in a store may move from [from] to [to]: forward
  /// only, and a rejection only of a build that is not approved yet.
  static bool _canAdvance(StoreState from, StoreState to) {
    const order = [
      StoreState.pending,
      StoreState.uploaded,
      StoreState.inReview,
      StoreState.approved,
      StoreState.live,
    ];
    if (to == StoreState.rejected) {
      return from == StoreState.uploaded || from == StoreState.inReview;
    }
    return from != StoreState.rejected &&
        order.indexOf(to) > order.indexOf(from);
  }

  // ---------------------------------------------------------------- manual

  /// Sets the status of the release [id] in [store] to [state], on the
  /// owner's word, as the device [by]: "Apple approved" and "Apple live" for
  /// Apple, "Play: live" for Google Play (D-14, D-15).
  ///
  /// Throws a [ReleaseForbiddenException] unless [by] is an `app` or `cli`
  /// token, a [ReleaseNotFoundException], a [ReleaseRequestException] for a
  /// status the owner cannot set or a store the release does not target,
  /// and a [ReleaseStateException] if the store has no build yet or is past
  /// that status.
  Future<Release> setStoreStatus(
    String id,
    ReleaseStore store,
    StoreState state, {
    required DeviceToken by,
  }) async {
    _requireOwner(by, 'set the status of a store');
    final allowed = switch (store) {
      ReleaseStore.apple => {StoreState.approved, StoreState.live},
      ReleaseStore.play => {StoreState.live},
    };
    if (!allowed.contains(state)) {
      throw ReleaseRequestException(
        'The status of ${store.wire} can be set to '
        '${allowed.map((s) => s.wire).join(' or ')} by hand, not '
        '${state.wire}.',
      );
    }
    return (await _locked(id, () async {
      final start = await _sync(id);
      final entry = start.stores[store];
      if (entry == null) {
        throw ReleaseRequestException(
          'The release ${start.id} does not go to ${store.wire}.',
        );
      }
      if (!_pollable.contains(entry.state) ||
          !_canAdvance(entry.state, state) ||
          start.state.isTerminal) {
        throw ReleaseStateException(
          '${store.wire} is ${entry.state.wire} for the release ${start.id}: '
          'it cannot be set to ${state.wire}.',
        );
      }
      final events = <EngineEvent>[];
      final now = _clock.now();
      var release = start.copyWith(
        stores: {
          ...start.stores,
          store: _storeChanged(
            start,
            entry.copyWith(
              state: state,
              source: StatusSource.manual,
              detail: 'manual',
              changedAt: now,
              note: null,
              ignored: null,
            ),
            events,
          ),
        },
      );
      release = _advance(release, events);
      return await _persist(start, release, events, by: by.name);
    })).toApi();
  }

  // ----------------------------------------------------------- new builds

  /// Starts a new build of the same version of the rejected release [id]
  /// (D-17): the workflow that released it runs again on its release branch,
  /// with a new build number (D-11) and the inputs of the first dispatch. Its
  /// gates ask for the owner's approval like any release.
  ///
  /// Throws a [ReleaseNotFoundException], a [ReleaseStateException] unless
  /// the release is `rejected`, and what the dispatch throws.
  Future<Run> newBuild(String id) async {
    final release = await sync(id);
    final branch = release.branch;
    if (release.state != ReleaseState.rejected || branch == null) {
      throw ReleaseStateException(
        'Only a rejected release gets a new build; ${release.id} is '
        '${release.state.wire}.',
      );
    }
    final last = (await _runRecords.get(release.runId))!;
    final first = DispatchRequest.fromJson(last.request);
    return await _dispatch(
      release.projectId,
      last.workflowId,
      DispatchRequest(
        ref: branch,
        app: release.appPath,
        flavors: [release.flavor],
        platforms: first.platforms,
        version: release.version,
        release: release.id,
        inputs: first.inputs,
      ),
    );
  }

  // ---------------------------------------------------------------- merging

  /// Requests the merge of the pull request of the release [id]: runs the
  /// `release-merge` workflow, whose merge waits for the owner's approval
  /// (D-13). The release must be `live`, which is when every store targeted
  /// is. Asking again while that run is under way returns it.
  ///
  /// Throws a [ReleaseNotFoundException], a [ReleaseStateException] unless
  /// the release is live and has its pull request, and what the dispatch
  /// throws.
  Future<Run> requestMerge(String id) async {
    final release = await sync(id);
    final running = release.mergeRunId;
    if (running != null) return await _runs.get(running);
    final branch = release.branch;
    if (release.state != ReleaseState.live ||
        release.prNumber == null ||
        branch == null) {
      throw ReleaseStateException(
        'The pull request of ${release.id} cannot be merged: it is '
        '${release.state.wire}'
        '${release.prNumber == null ? ' and has no pull request' : ''}. '
        'Merging opens once every store is live.',
      );
    }
    final workflow = (await _workflows.list(release.projectId))
        .firstWhere((workflow) => workflow.name == releaseMergeWorkflow);
    return await _dispatch(
      release.projectId,
      workflow.id,
      DispatchRequest(
        ref: branch,
        app: release.appPath,
        flavors: [release.flavor],
        releaseVersion: '${release.version}+${release.build}',
        release: release.id,
      ),
    );
  }

  // --------------------------------------------------------------- rollout

  /// Requests the rollout change [request] of the release [id] (U7a): runs
  /// the `release-rollout` workflow on the commit of the release, whose
  /// change waits for the owner's approval (D-13).
  ///
  /// Throws a [ReleaseNotFoundException], a [ReleaseStateException] unless
  /// the stores approved the release and it went to the store of [request],
  /// a [ReleaseRequestException] for a change the store cannot make, and
  /// what the dispatch throws.
  Future<Run> requestRollout(String id, RolloutRequest request) async {
    if (request.problem case final problem?) {
      throw ReleaseRequestException(problem);
    }
    final release = await sync(id);
    if (!_rolledOut.contains(release.state)) {
      throw ReleaseStateException(
        'The rollout of ${release.id} cannot change: it is '
        '${release.state.wire}. A rollout changes once the stores approved '
        'the release.',
      );
    }
    if (!release.stores.containsKey(request.store)) {
      throw ReleaseStateException(
        'The release ${release.id} did not go to ${request.store.wire}.',
      );
    }
    final workflow = (await _workflows.list(release.projectId))
        .firstWhere((workflow) => workflow.name == releaseRolloutWorkflow);
    return await _dispatch(
      release.projectId,
      workflow.id,
      DispatchRequest(
        ref: release.tag ?? release.branch,
        app: release.appPath,
        flavors: [release.flavor],
        releaseVersion: '${release.version}+${release.build}',
        release: release.id,
        inputs: {
          'store': request.store.wire,
          'action': request.action.wire,
          'userFraction': ?request.userFraction,
        },
      ),
    );
  }

  // ---------------------------------------------------------------- patches

  /// Requests [action] on the Shorebird patch [patchNumber] of the release
  /// [id] (U7b): runs the `shorebird-track` workflow, whose change waits for
  /// the owner's approval at `gate: prod_patch` (D-13).
  ///
  /// Throws a [ReleaseNotFoundException], a [ReleaseStateException] unless
  /// the stores approved the release, a [ReleaseRequestException] for a
  /// patch the release has no record of, and what the dispatch throws.
  Future<Run> requestPatch(
    String id,
    int patchNumber,
    PatchAction action,
  ) async {
    final release = await sync(id);
    if (!_rolledOut.contains(release.state)) {
      throw ReleaseStateException(
        'A patch of ${release.id} cannot move: it is ${release.state.wire}.',
      );
    }
    final patched = (await _releases.events(release.id)).any(
      (event) =>
          event.kind == ReleaseEventKind.patch &&
          event.patchNumber == patchNumber,
    );
    if (!patched) {
      throw ReleaseRequestException(
        'The release ${release.id} has no patch $patchNumber that XPath '
        'published.',
      );
    }
    final workflow = (await _workflows.list(release.projectId))
        .firstWhere((workflow) => workflow.name == shorebirdTrackWorkflow);
    final run = await _dispatch(
      release.projectId,
      workflow.id,
      DispatchRequest(
        ref: release.tag ?? release.branch,
        app: release.appPath,
        flavors: [release.flavor],
        releaseVersion: '${release.version}+${release.build}',
        release: release.id,
        inputs: {'patchNumber': patchNumber, 'action': action.wire},
      ),
    );
    await _releases.addEvent(
      release.id,
      ReleaseEvent(
        kind: ReleaseEventKind.patchRequested,
        at: _clock.now(),
        detail: action.wire,
        runId: run.id,
        patchNumber: patchNumber,
      ),
    );
    return run;
  }

  // ----------------------------------------------------------------- texts

  /// Sets the texts the uploads of the release [id] send to the stores
  /// (U7b), as the device [by]. A blank text is cleared.
  ///
  /// Throws a [ReleaseForbiddenException] unless [by] is an `app` or `cli`
  /// token, a [ReleaseNotFoundException], and a [ReleaseStateException] for
  /// an abandoned release.
  Future<Release> setTexts(
    String id,
    ReleaseTexts texts, {
    required DeviceToken by,
  }) async {
    _requireOwner(by, 'change the texts of a release');
    String? clean(String? text) =>
        text == null || text.trim().isEmpty ? null : text.trim();
    return (await _locked(id, () async {
      final start = await _require(id);
      if (start.state == ReleaseState.abandoned) {
        throw ReleaseStateException('The release ${start.id} is abandoned.');
      }
      final next = start.copyWith(
        whatsNew: clean(texts.whatsNew),
        whatToTest: clean(texts.whatToTest),
      );
      if (next == start) return start;
      final saved = next.copyWith(updatedAt: _clock.now());
      await _releases.update(saved);
      await _releases.addEvent(
        saved.id,
        ReleaseEvent(
          kind: ReleaseEventKind.texts,
          at: saved.updatedAt,
          by: by.name,
        ),
      );
      return saved;
    })).toApi();
  }

  /// What happened to the release [id], oldest first (U7b).
  ///
  /// Throws a [ReleaseNotFoundException] if there is none.
  Future<ReleaseHistory> history(String id) async {
    await _require(id);
    return ReleaseHistory(await _releases.events(id));
  }

  // --------------------------------------------------------------- abandon

  /// Gives the release [id] up, as the device [by]. A run that still builds it
  /// is cancelled.
  ///
  /// Throws a [ReleaseForbiddenException] unless [by] is an `app` or `cli`
  /// token, a [ReleaseNotFoundException] and a [ReleaseStateException] if the
  /// release is over.
  Future<Release> abandon(
    String id, {
    required DeviceToken by,
    String? reason,
  }) async {
    _requireOwner(by, 'abandon a release');
    final abandoned = await _locked(id, () async {
      final start = await _sync(id);
      if (start.state.isTerminal) {
        throw ReleaseStateException(
          'The release ${start.id} is ${start.state.wire}.',
        );
      }
      final text = reason?.trim();
      return await _save(
        start,
        _move(
          start.copyWith(
            message: text == null || text.isEmpty ? 'Abandoned.' : text,
          ),
          ReleaseState.abandoned,
        ),
        by: by.name,
      );
    });
    await _cancelBuild(abandoned);
    return abandoned.toApi();
  }

  Future<void> _cancelBuild(ReleaseRecord release) async {
    try {
      await _runs.cancel(release.runId);
    } on RunException {
      // Every job of the run ended already, or it is gone: nothing to stop.
    }
  }

  // --------------------------------------------------------------- helpers

  static void _requireOwner(DeviceToken by, String what) {
    if (by.kind != DeviceTokenKind.app && by.kind != DeviceTokenKind.cli) {
      throw ReleaseForbiddenException(
        'A ${by.kind.name} token cannot $what: only the app or `xp` do.',
      );
    }
  }

  Future<ReleaseRecord> _require(String id) async =>
      await _releases.get(id) ?? (throw ReleaseNotFoundException(id));

  /// Runs [action] after every earlier action on the release [id].
  Future<T> _locked<T>(String id, Future<T> Function() action) async {
    final previous = _tails[id] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = _tails[id] = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      _tails.removeWhere((key, value) => key == id && identical(value, tail));
    }
  }

  /// [release] in state [to]; announces the move on [events] if given.
  ///
  /// Throws a [ReleaseTransitionException] for a move D-17 does not allow.
  ReleaseRecord _move(
    ReleaseRecord release,
    ReleaseState to, [
    List<EngineEvent>? events,
  ]) {
    ReleaseStateMachine.move(release.state, to);
    events?.add(
      ReleaseStateChanged(
        releaseId: release.id,
        projectId: release.projectId,
        from: release.state,
        to: to,
      ),
    );
    return release.copyWith(state: to);
  }

  /// [entry], and an event that its status changed.
  StoreEntry _storeChanged(
    ReleaseRecord release,
    StoreEntry entry,
    List<EngineEvent> events,
  ) {
    events.add(
      ReleaseStoreChanged(
        releaseId: release.id,
        projectId: release.projectId,
        store: entry.store,
        state: entry.state,
        source: entry.source,
      ),
    );
    return entry;
  }

  /// Stores [release] if it differs from [start], adds what changed to its
  /// history (as done by the device named [by], when one did it), then
  /// announces [events].
  Future<ReleaseRecord> _persist(
    ReleaseRecord start,
    ReleaseRecord release,
    List<EngineEvent> events, {
    String? by,
  }) async {
    if (release == start) return start;
    final saved = release.copyWith(updatedAt: _clock.now());
    await _releases.update(saved);
    for (final event in events) {
      final entry = switch (event) {
        ReleaseStoreChanged(:final store, :final state, :final source) =>
          ReleaseEvent(
            kind: ReleaseEventKind.store,
            at: saved.updatedAt,
            store: store,
            detail: state.wire,
            by: source == StatusSource.manual ? by : null,
          ),
        ReleaseStateChanged(to: ReleaseState.merged) => ReleaseEvent(
          kind: ReleaseEventKind.merged,
          at: saved.updatedAt,
          detail: saved.mergeCommit,
          runId: start.mergeRunId,
        ),
        ReleaseStateChanged(to: ReleaseState.abandoned) => ReleaseEvent(
          kind: ReleaseEventKind.abandoned,
          at: saved.updatedAt,
          detail: saved.message,
          by: by,
        ),
        _ => null,
      };
      if (entry != null) await _releases.addEvent(saved.id, entry);
    }
    events.forEach(_events.append);
    return saved;
  }

  /// Stores [next] in place of [start] and announces the move between them.
  Future<ReleaseRecord> _save(
    ReleaseRecord start,
    ReleaseRecord next, {
    bool storeEvents = false,
    String? by,
  }) async {
    final events = <EngineEvent>[
      if (next.state != start.state)
        ReleaseStateChanged(
          releaseId: next.id,
          projectId: next.projectId,
          from: start.state,
          to: next.state,
        ),
      if (storeEvents)
        for (final entry in next.stores.values)
          ReleaseStoreChanged(
            releaseId: next.id,
            projectId: next.projectId,
            store: entry.store,
            state: entry.state,
            source: entry.source,
          ),
    ];
    return await _persist(start, next, events, by: by);
  }

  String _newId() {
    final hex = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    );
    return 'rel_${hex.join()}';
  }
}
