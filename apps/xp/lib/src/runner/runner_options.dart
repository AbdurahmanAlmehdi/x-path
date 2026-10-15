import 'package:args/args.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';

/// The data directory the options name, or the default one of [host].
RunnerPaths runnerPathsOf(ArgResults results, RunnerHost host) {
  final directory = results.option('data-dir');
  return directory == null
      ? RunnerPaths.fromEnvironment(host.environment, host.home)
      : RunnerPaths(directory);
}

/// Adds `--data-dir` to [parser].
void addRunnerDataDirOption(ArgParser parser) => parser.addOption(
  'data-dir',
  help:
      r'Where the runner keeps its files (default: $XP_RUNNER_DATA_DIR, else '
      '~/.local/share/xpath/runner).',
  valueHelp: 'dir',
);
