import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// What an approval is about, beyond its own fields: the job that waits for
/// it and the release that job builds. Either is `null` when the engine
/// does not say (or cannot be reached).
class ApprovalSubject extends Equatable {
  const new({this.job, this.release});

  final Job? job;
  final Release? release;

  @override
  List<Object?> get props => [job, release];
}

/// Reads the job of [approval] and the release it builds.
Future<ApprovalSubject> loadApprovalSubject(
  Approval approval, {
  required JobsRepository jobs,
  required ReleasesRepository releases,
}) async {
  final jobId = approval.jobId;
  if (jobId == null) return const ApprovalSubject();
  final Job job;
  try {
    job = (await jobs.watchJob(jobId).first).value;
  } on Object {
    return const ApprovalSubject();
  }
  final releaseId = job.releaseId;
  if (releaseId == null) return ApprovalSubject(job: job);
  try {
    final release = (await releases.watchRelease(releaseId).first).value;
    return ApprovalSubject(job: job, release: release);
  } on Object {
    return ApprovalSubject(job: job);
  }
}
