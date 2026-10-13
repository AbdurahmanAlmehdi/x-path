import 'dart:async';

import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/toolchain/tool_report.dart';
import 'package:xp_engine/src/toolchain/version_parsers.dart';

/// Finds out which of the tools that XPath uses are on this machine, and
/// which version (D-20).
///
/// Shorebird and `gh` are managed per machine and Xcode is only detected:
/// nothing here installs or updates anything, and no minimum version is
/// enforced; the versions are recorded with each job. The probes are the
/// primitives for the capability checks of the runners (D-19): the engine
/// asks the machine instead of trusting what a runner says about itself.
class ToolProber {
  /// Creates a prober that runs programs with [_runner].
  ///
  /// [isMacOS] tells whether Xcode can exist. The executables are looked up in
  /// `PATH`; pass full paths when the engine runs with a short one (a
  /// LaunchAgent). Each program has [timeout] to answer.
  const new({
    required this._runner,
    required this.isMacOS,
    this.shorebirdExecutable = 'shorebird',
    this.ghExecutable = 'gh',
    this.timeout = const Duration(seconds: 30),
  });

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// The Shorebird CLI.
  final String shorebirdExecutable;

  /// The GitHub CLI.
  final String ghExecutable;

  /// How long each program has to answer.
  final Duration timeout;

  final ProcessRunner _runner;

  /// All the tools, in the order `shorebird`, `gh`, `xcode`.
  Future<List<ToolReport>> probeAll() =>
      Future.wait([shorebird(), gh(), xcode()]);

  /// `shorebird --version`.
  Future<ToolReport> shorebird() => _probe(
    'shorebird',
    shorebirdExecutable,
    ['--version'],
    fix: 'Install the Shorebird CLI: https://docs.shorebird.dev',
    parse: (stdout) {
      final version = parseShorebirdVersion(stdout);
      return version == null
          ? null
          : ToolReport('shorebird', ToolStatus.available, version: version);
    },
  );

  /// `gh --version`.
  Future<ToolReport> gh() => _probe(
    'gh',
    ghExecutable,
    ['--version'],
    fix: 'Install the GitHub CLI: https://cli.github.com',
    parse: (stdout) {
      final version = parseGhVersion(stdout);
      return version == null
          ? null
          : ToolReport('gh', ToolStatus.available, version: version);
    },
  );

  /// The selected Xcode: `xcode-select -p`, then `xcodebuild -version`.
  ///
  /// Not available on Linux. `xcodebuild` is only run once Xcode is selected,
  /// because on a Mac with no developer tools at all macOS answers it with a
  /// dialog.
  Future<ToolReport> xcode() async {
    if (!isMacOS) {
      return const ToolReport(
        'xcode',
        ToolStatus.unsupported,
        message: 'Xcode is not available on this operating system.',
      );
    }
    const fix = 'Install Xcode and select it with xcode-select -s.';
    final selected = await _run('xcode-select', ['-p']);
    if (selected is! ProcessOutput || selected.exitCode != 0) {
      return _failure('xcode', selected, fix);
    }
    final developerDir = selected.stdout.trim();
    return await _probe(
      'xcode',
      'xcodebuild',
      ['-version'],
      fix: fix,
      parse: (stdout) {
        final xcode = parseXcodeVersion(stdout);
        if (xcode == null) return null;
        final build = xcode.build;
        return ToolReport(
          'xcode',
          ToolStatus.available,
          version: xcode.version,
          detail: '${build == null ? '' : 'build $build, '}$developerDir',
        );
      },
    );
  }

  Future<ToolReport> _probe(
    String tool,
    String executable,
    List<String> arguments, {
    required String fix,
    required ToolReport? Function(String stdout) parse,
  }) async {
    final result = await _run(executable, arguments);
    if (result is! ProcessOutput || result.exitCode != 0) {
      return _failure(tool, result, fix);
    }
    return parse(result.stdout) ??
        ToolReport(
          tool,
          ToolStatus.failed,
          message:
              '$executable ${arguments.join(' ')} printed no version I '
              'understand: ${_firstLine(result.stdout)}',
        );
  }

  /// The output, a [ProcessStartException] or a [TimeoutException].
  Future<Object> _run(String executable, List<String> arguments) async {
    try {
      return await _runner.run(
        executable,
        arguments,
        environment: const {
          'GH_PROMPT_DISABLED': '1',
          'GH_NO_UPDATE_NOTIFIER': '1',
          'NO_COLOR': '1',
        },
        timeout: timeout,
      );
    } on ProcessStartException catch (error) {
      return error;
    } on TimeoutException catch (error) {
      return error;
    }
  }

  ToolReport _failure(String tool, Object result, String fix) =>
      switch (result) {
        ProcessStartException() => ToolReport(
          tool,
          ToolStatus.missing,
          message: '${result.executable} was not found. $fix',
        ),
        ProcessOutput() => ToolReport(
          tool,
          ToolStatus.failed,
          message:
              'It exited with ${result.exitCode}: ${_errorLine(result)}. $fix',
        ),
        _ => ToolReport(
          tool,
          ToolStatus.failed,
          message: 'It did not answer in time.',
        ),
      };
}

String _errorLine(ProcessOutput output) =>
    _firstLine(output.stderr.isEmpty ? output.stdout : output.stderr);

String _firstLine(String text) => text.trim().split('\n').first.trim();
