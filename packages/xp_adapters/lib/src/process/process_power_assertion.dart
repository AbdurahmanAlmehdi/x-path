import 'dart:async';

import 'package:xp_engine/xp_engine.dart';

/// Keeps the machine awake for as long as a helper process runs.
///
/// A [PowerAssertion] over a [ProcessRunner]: [hold] starts the helper,
/// [release] stops it. A machine without the helper gets a warning and no
/// assertion; jobs run all the same.
class ProcessPowerAssertion implements PowerAssertion {
  /// Creates an assertion that runs [executable] with [arguments].
  new({
    required this._runner,
    required this.executable,
    required this.arguments,
    this._onWarning,
  });

  /// The helper program.
  final String executable;

  /// Its arguments.
  final List<String> arguments;

  final ProcessRunner _runner;
  final void Function(String message)? _onWarning;
  RunningProcess? _helper;

  /// Whether the helper runs.
  bool get isHeld => _helper != null;

  @override
  Future<void> hold() async {
    if (_helper != null) return;
    try {
      final helper = await _runner.start(executable, arguments);
      _helper = helper;
      unawaited(
        helper.result.then((output) {
          if (_helper != helper) return;
          _helper = null;
          _onWarning?.call(
            '$executable ended by itself (exit code ${output.exitCode}); the '
            'machine may go to sleep while jobs run.',
          );
        }),
      );
    } on ProcessStartException catch (error) {
      _onWarning?.call(
        'Cannot keep the machine awake: ${error.message} ($executable). The '
        'machine may go to sleep while jobs run.',
      );
    }
  }

  @override
  Future<void> release() async {
    final helper = _helper;
    if (helper == null) return;
    _helper = null;
    helper.kill();
    await helper.result;
  }
}

/// The power assertion for the machine [operatingSystem] (as in
/// `Platform.operatingSystem`) that `xpd` with process id [pid] runs on.
///
/// - `macos`: `caffeinate -i -w <pid>` prevents idle sleep while `xpd` lives,
///   so it ends by itself if `xpd` is killed.
/// - `linux`: `systemd-inhibit --what=sleep:idle ... sleep infinity` holds a
///   sleep and idle inhibitor lock.
/// - anything else: nothing is held, and [onWarning] is told so.
PowerAssertion createPowerAssertion({
  required ProcessRunner runner,
  required String operatingSystem,
  required int pid,
  void Function(String message)? onWarning,
}) => switch (operatingSystem) {
  'macos' => ProcessPowerAssertion(
    runner: runner,
    executable: 'caffeinate',
    arguments: ['-i', '-w', '$pid'],
    onWarning: onWarning,
  ),
  'linux' => ProcessPowerAssertion(
    runner: runner,
    executable: 'systemd-inhibit',
    arguments: [
      '--what=sleep:idle',
      '--who=XPath',
      '--why=XPath is running a job',
      '--mode=block',
      'sleep',
      'infinity',
    ],
    onWarning: onWarning,
  ),
  _ => _Unsupported(operatingSystem, onWarning),
};

class _Unsupported implements PowerAssertion {
  new(this._operatingSystem, this._onWarning);

  final String _operatingSystem;
  final void Function(String message)? _onWarning;

  @override
  Future<void> hold() async => _onWarning?.call(
    'XPath cannot keep a $_operatingSystem machine awake. The machine may go '
    'to sleep while jobs run.',
  );

  @override
  Future<void> release() async {}
}
