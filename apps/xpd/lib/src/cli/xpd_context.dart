import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

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
    this.ghFallbackPaths = defaultGhFallbackPaths,
    this.processes = const IoProcessRunner(),
    this.executable = '',
    this.serviceManager,
  });

  /// Where Homebrew puts `gh` on Apple Silicon and on Intel Macs. `launchd`
  /// starts the engine with a `PATH` that has neither directory.
  static const defaultGhFallbackPaths = [
    '/opt/homebrew/bin/gh',
    '/usr/local/bin/gh',
  ];

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

  /// Where to look for the GitHub CLI when it is not on `PATH`.
  final List<String> ghFallbackPaths;

  /// Starts the programs the service commands run (`launchctl`, `systemctl`).
  final ProcessRunner processes;

  /// The path of the running `xpd` executable, as the operating system
  /// resolves it (`Platform.resolvedExecutable`): inside an installed bundle
  /// it is `<bundle>/bin/xpd`. Empty when it is not known.
  final String executable;

  /// Makes the service manager for a scope, instead of the one of this
  /// machine. Tests use it to keep the unit files in a temporary folder.
  final ServiceManager Function(ServiceScope scope)? serviceManager;

  /// This context with [out], [err] and [environment] replaced.
  XpdContext copyWith({
    StringSink? out,
    StringSink? err,
    Map<String, String>? environment,
  }) => XpdContext(
    out: out ?? this.out,
    err: err ?? this.err,
    shutdown: shutdown,
    environment: environment ?? this.environment,
    operatingSystem: operatingSystem,
    ghFallbackPaths: ghFallbackPaths,
    processes: processes,
    executable: executable,
    serviceManager: serviceManager,
  );
}
