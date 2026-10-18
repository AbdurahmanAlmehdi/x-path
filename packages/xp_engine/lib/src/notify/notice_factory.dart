import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/notify/notice.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/releases/release_record.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';

/// Decides which engine events the owner hears about, and what to tell
/// (D-22): a production job failed or succeeded, an approval was asked,
/// decided or ran out, a release was rejected, approved, went live or was
/// merged, a credential expired, the secrets are locked (D-10), and a build is
/// live in a store (the `min_version_*` reminder).
///
/// Every other event is nothing to tell. The text is run through the masker
/// and never carries more than names, versions, short commits and what the
/// engine itself said, so it holds no secret.
class NoticeFactory {
  /// Creates the factory.
  new({
    required this._projects,
    required this._releases,
    required this._jobs,
    required this._runs,
    required this._masker,
  });

  /// The longest body: a failed job's message can be a page of tool output.
  static const maxBodyLength = 600;

  final ProjectRepository _projects;
  final ReleaseRepository _releases;
  final JobRepository _jobs;
  final RunRepository _runs;
  final OutputMasker _masker;

  /// The notice for [event], or `null` if it is not one to tell.
  Future<Notice?> describe(EngineEvent event) async => switch (event) {
    JobStateChanged(:final jobId, :final state)
        when state == JobState.failed || state == JobState.succeeded =>
      await _job(jobId, state),
    ApprovalRequested() => await _approvalRequested(event),
    ApprovalDecided() => await _approvalDecided(event),
    ApprovalExpired() => await _approvalExpired(event),
    ReleaseStateChanged(:final to)
        when const {
          ReleaseState.rejected,
          ReleaseState.approved,
          ReleaseState.live,
          ReleaseState.merged,
        }.contains(to) =>
      await _release(event),
    ReleaseStoreChanged(:final state) when state == StoreState.live =>
      await _minVersion(event),
    CredentialExpired() => await _credentialExpired(event),
    _ => null,
  };

  /// The notice for secrets that cannot be reached (D-10).
  Notice secretsLocked() => const Notice(
    kind: NotificationKind.secretsLocked,
    level: NotificationLevel.error,
    title: 'Secrets are locked',
    body:
        'The engine cannot reach its secrets, so jobs that need them wait. '
        'Unlock the Keychain on the engine machine; the engine does not ask '
        'for it.',
    key: 'secrets_locked',
  );

  // ------------------------------------------------------------------ jobs

  Future<Notice?> _job(String jobId, JobState state) async {
    final job = await _jobs.get(jobId);
    if (job == null || !await _isProduction(job)) return null;
    final failed = state == JobState.failed;
    final project = await _projectName(job.projectId);
    final message = job.message?.trim();
    final detail = failed && message != null && message.isNotEmpty
        ? ' - $message'
        : '';
    return Notice(
      kind: failed ? NotificationKind.jobFailed : NotificationKind.jobSucceeded,
      level: failed ? NotificationLevel.error : NotificationLevel.success,
      title: failed ? 'Production job failed' : 'Production job succeeded',
      body: _clean('$project: ${job.name ?? job.id}$detail'),
      key: '${failed ? 'job_failed' : 'job_succeeded'}:$jobId',
      projectId: job.projectId,
      jobId: jobId,
      releaseId: job.releaseId,
    );
  }

  /// A job is a production job when it belongs to a release or to a run that
  /// holds the project lock (a production release or patch, D-11).
  Future<bool> _isProduction(JobRecord job) async {
    if (job.releaseId != null) return true;
    final runId = job.runId;
    if (runId == null) return false;
    return (await _runs.get(runId))?.locksProject ?? false;
  }

  // ------------------------------------------------------------- approvals

  Future<Notice> _approvalRequested(ApprovalRequested event) async {
    final project = await _projectName(event.projectId);
    final version = event.version == null ? '' : ' ${event.version}';
    return Notice(
      kind: NotificationKind.approvalRequested,
      level: NotificationLevel.warning,
      title: 'Approval needed: ${_action(event.action)}',
      body: _clean(
        '$project asks to ${_action(event.action)} at '
        '${_short(event.sha)}$version. Approve in the app or with '
        '`xp approve ${event.approvalId}` before ${_utc(event.expiresAt)}.',
      ),
      key: 'approval_requested:${event.approvalId}',
      projectId: event.projectId,
      approvalId: event.approvalId,
    );
  }

  Future<Notice> _approvalDecided(ApprovalDecided event) async {
    final project = await _projectName(event.projectId);
    final approved = event.state == ApprovalState.approved;
    final by = event.decidedBy;
    return Notice(
      kind: NotificationKind.approvalDecided,
      level: approved ? NotificationLevel.success : NotificationLevel.warning,
      title: '${approved ? 'Approved' : 'Denied'}: ${_action(event.action)}',
      body: _clean(
        '${by.name} (${by.kind.name}) ${approved ? 'approved' : 'denied'} '
        'the request to ${_action(event.action)} in $project.',
      ),
      key: 'approval_decided:${event.approvalId}',
      projectId: event.projectId,
      approvalId: event.approvalId,
    );
  }

  Future<Notice> _approvalExpired(ApprovalExpired event) async {
    final project = await _projectName(event.projectId);
    return Notice(
      kind: NotificationKind.approvalExpired,
      level: NotificationLevel.warning,
      title: 'Approval expired: ${_action(event.action)}',
      body: _clean(
        'Nobody decided the request to ${_action(event.action)} in $project '
        'in time, so it counts as denied.',
      ),
      key: 'approval_expired:${event.approvalId}',
      projectId: event.projectId,
      approvalId: event.approvalId,
    );
  }

  // -------------------------------------------------------------- releases

  Future<Notice?> _release(ReleaseStateChanged event) async {
    final release = await _releases.get(event.releaseId);
    if (release == null) return null;
    final label = await _releaseLabel(release);
    final (kind, level, title, body) = switch (event.to) {
      ReleaseState.rejected => (
        NotificationKind.releaseRejected,
        NotificationLevel.error,
        'Release rejected',
        '$label was rejected. ${_rejections(release)}Start a new build of the '
            'same version from the app.',
      ),
      ReleaseState.approved => (
        NotificationKind.releaseApproved,
        NotificationLevel.success,
        'Release approved',
        '$label was approved by the stores.',
      ),
      ReleaseState.live => (
        NotificationKind.releaseLive,
        NotificationLevel.success,
        'Release live',
        '$label is on sale in every store it targets. The release pull '
            'request can be merged.',
      ),
      _ => (
        NotificationKind.releaseMerged,
        NotificationLevel.success,
        'Release merged',
        'The pull request of $label was merged.',
      ),
    };
    return Notice(
      kind: kind,
      level: level,
      title: title,
      body: _clean(body),
      key: '${kind.wire}:${release.id}',
      projectId: release.projectId,
      releaseId: release.id,
    );
  }

  String _rejections(ReleaseRecord release) {
    final texts = [
      for (final entry in release.stores.values)
        if (entry.state == StoreState.rejected)
          '${_storeName(entry.store)}: ${entry.detail ?? 'rejected'}. ',
    ];
    return texts.join();
  }

  /// The `min_version_*` reminder (D-22): a build became available in a
  /// store, which is when the minimum version of that platform in Remote
  /// Config may be raised. XPath does not know whether a release is a forced
  /// update, so the text says "if".
  Future<Notice?> _minVersion(ReleaseStoreChanged event) async {
    final release = await _releases.get(event.releaseId);
    if (release == null) return null;
    final variable = switch (event.store) {
      ReleaseStore.apple => 'min_version_ios',
      ReleaseStore.play => 'min_version_android',
    };
    final label = await _releaseLabel(release);
    return Notice(
      kind: NotificationKind.minVersionReminder,
      level: NotificationLevel.info,
      title: 'Raise $variable if this is a forced update',
      body: _clean(
        '$label is live in ${_store(event.store)}. If it is a forced update, '
        'raise $variable to ${release.version} in Firebase Remote Config '
        'now. Raising it earlier locks out users who have nothing to update '
        'to.',
      ),
      key: 'min_version:${release.id}:${event.store.wire}',
      projectId: release.projectId,
      releaseId: release.id,
    );
  }

  // ----------------------------------------------------------- credentials

  Future<Notice> _credentialExpired(CredentialExpired event) async {
    final projectId = event.projectId;
    final where = projectId == null
        ? null
        : [
            await _projectName(projectId),
            if (event.app case final app? when app != '.') app,
            ?event.flavor,
          ].join(' ');
    final name = event.name == null ? '' : ' "${event.name}"';
    return Notice(
      kind: NotificationKind.credentialExpired,
      level: NotificationLevel.error,
      title: 'Credential expired: ${event.kind.wire}$name',
      body: _clean(where == null ? event.message : '$where: ${event.message}'),
      key: [
        'credential_expired:${event.credentialId}',
        if (event.flavor != null) '$projectId:${event.app}:${event.flavor}',
      ].join(':'),
      projectId: projectId,
    );
  }

  // --------------------------------------------------------------- helpers

  Future<String> _projectName(String projectId) async =>
      (await _projects.get(projectId))?.fullName ?? projectId;

  Future<String> _releaseLabel(ReleaseRecord release) async {
    final project = await _projectName(release.projectId);
    final flavor = release.flavor.isEmpty ? '' : ' ${release.flavor}';
    return '$project$flavor ${release.version} (${release.build})';
  }

  static String _storeName(ReleaseStore store) => switch (store) {
    ReleaseStore.apple => 'App Store',
    ReleaseStore.play => 'Google Play',
  };

  static String _store(ReleaseStore store) =>
      store == ReleaseStore.apple ? 'the App Store' : 'Google Play';

  static String _action(String action) => action.replaceAll('_', ' ');

  static String _short(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;

  static String _utc(DateTime time) {
    final utc = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)} UTC';
  }

  /// Hides known secrets in [text] and cuts it to [maxBodyLength].
  String _clean(String text) {
    final stream = _masker.newStream();
    final masked = stream.add(text) + stream.flush();
    final flat = masked.trim();
    return flat.length <= maxBodyLength
        ? flat
        : '${flat.substring(0, maxBodyLength - 3)}...';
  }
}
