/// What the `xpd` commands run against: the streams they print to and the
/// process around them. Tests pass fakes.
class XpdContext {
  /// Creates a context.
  const new({
    required this.out,
    required this.err,
    required this.shutdown,
    required this.environment,
    required this.operatingSystem,
  });

  /// Where results go.
  final StringSink out;

  /// Where diagnostics go.
  final StringSink err;

  /// Emits when the process is asked to stop (SIGINT or SIGTERM).
  final Stream<void> shutdown;

  /// The environment variables.
  final Map<String, String> environment;

  /// `macos`, `linux`, ... as in `Platform.operatingSystem`.
  final String operatingSystem;
}
