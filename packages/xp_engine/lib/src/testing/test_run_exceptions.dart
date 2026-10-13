/// There is no test run for the job asked for.
class TestRunNotFoundException implements Exception {
  /// Creates an exception for the job [jobId].
  const new(this.jobId) : message = 'Job $jobId has no test run.';

  /// The job that was asked for.
  final String jobId;

  /// What went wrong.
  final String message;

  @override
  String toString() => 'TestRunNotFoundException: $message';
}
