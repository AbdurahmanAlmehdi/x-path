import 'package:xp_engine/src/process/output_line.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';

/// A program a step runs.
class ProcessCommand {
  /// Creates a command.
  const new(
    this.executable, {
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
    this.passThroughEnvironment = const [],
    this.secretEnvironment = const {},
    this.secretFiles = const {},
  });

  /// The program, looked up in `PATH`.
  final String executable;

  /// Its arguments. Never put a secret here: arguments show up in `ps`.
  final List<String> arguments;

  /// The directory to run in, or `null` for the engine's.
  final String? workingDirectory;

  /// Variables the step sets itself.
  final Map<String, String> environment;

  /// Names of variables the process needs from the engine's own environment
  /// on top of the allowed ones (`allowlistedEnvironment`).
  final List<String> passThroughEnvironment;

  /// Secrets passed in the environment: variable name to secret key. The
  /// engine reads the value from the secret store.
  final Map<String, String> secretEnvironment;

  /// Secrets passed as files: variable name to secret key. The variable holds
  /// the path of a file with mode 0600 in a folder that is deleted when the
  /// job ends.
  final Map<String, String> secretFiles;
}

/// What a step may use while it runs.
abstract interface class StepContext {
  /// The job the step belongs to.
  String get jobId;

  /// The position of the step in the job.
  int get ordinal;

  /// Whether the job was cancelled or the engine is stopping. A step should
  /// stop what it does soon after this turns true.
  bool get isStopping;

  /// Runs [command] to its end and returns how it ended.
  ///
  /// The environment is the allowed one plus what the command declares; known
  /// secrets are masked in every line before it is stored or streamed. The
  /// lines go to the job's log, and to [onLine] when given, for steps that
  /// parse the output of a tool. If the job is cancelled the process group is
  /// stopped and the result says `cancelled`.
  ///
  /// Throws a `ProcessStartException` if the program cannot be started, a
  /// `ToolchainException` if the machine cannot supervise processes and a
  /// `SecretStoreException` if a secret cannot be read.
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  });

  /// The text of the define file stored as the secret [secretKey]. Its values
  /// are masked in all output from now on.
  ///
  /// Throws a `SecretStoreException` if the secret cannot be read.
  Future<String> readDartDefines(String secretKey);

  /// Writes [contents] to a file with mode 0600 in the job's secret folder,
  /// which is deleted when the job ends, and returns its path.
  Future<String> writeSecretFile(String name, String contents);
}
