import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/testing/test_run_results.dart';

/// The longest message or stack trace kept per test. Longer text is cut, so
/// that one test cannot make a stored run large.
const maxTestDetailLength = 4000;

/// What a finished `flutter test --machine` run reported.
class ParsedTestRun {
  /// Creates a parsed run.
  const new({required this.results, required this.success});

  /// Every test, by identity.
  final TestRunResults results;

  /// What the runner said: whether all tests passed.
  final bool success;
}

/// Reads the output of `flutter test --machine`, a JSON event per line
/// (package:test's JSON reporter), into per-test results (D-21).
///
/// Feed the lines as they arrive with [addLine]; [finish] gives the run once
/// the `done` event was seen. Lines that are not JSON objects are noise
/// (Flutter prints blank lines and `[{"event":...}]` notices in between) and
/// are ignored.
///
/// The identity of a test is its file relative to [appDirectory] and its full
/// name, which already has the names of its groups. The runner reports a test
/// file it fails to load, and a failing `setUpAll`, as tests of their own
/// (`loading test/x_test.dart`, `group (setUpAll)`), so that they fail the
/// run like any other test.
class MachineTestParser {
  /// Creates a parser for a run in [appDirectory], which is removed from the
  /// paths in the output.
  new({required this.appDirectory});

  /// The app directory the tests ran in, absolute.
  final String appDirectory;

  final _suites = <int, String>{};
  final _running = <int, _RunningTest>{};
  final _tests = <TestCase>[];
  var _events = 0;
  bool? _success;

  /// How many JSON events were read.
  int get events => _events;

  /// Reads one line of output.
  void addLine(String line) {
    final text = line.trim();
    if (!text.startsWith('{')) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final type = decoded['type'];
    if (type is! String) return;
    _events++;
    switch (type) {
      case 'suite':
        _onSuite(decoded);
      case 'testStart':
        _onTestStart(decoded);
      case 'error':
        _onError(decoded);
      case 'testDone':
        _onTestDone(decoded);
      case 'done':
        _success = decoded['success'] == true;
    }
  }

  /// The run, or `null` if the output has no `done` event: the process
  /// stopped before the run was over, or printed no machine output at all.
  ParsedTestRun? finish() {
    final success = _success;
    if (success == null) return null;
    return ParsedTestRun(results: TestRunResults.of(_tests), success: success);
  }

  void _onSuite(Map<String, dynamic> event) {
    final suite = event['suite'];
    if (suite is Map<String, dynamic> &&
        suite['id'] is int &&
        suite['path'] is String) {
      _suites[suite['id'] as int] = _relative(suite['path'] as String);
    }
  }

  void _onTestStart(Map<String, dynamic> event) {
    final test = event['test'];
    if (test is Map<String, dynamic> &&
        test['id'] is int &&
        test['name'] is String) {
      _running[test['id'] as int] = _RunningTest(
        suite: _suites[test['suiteID']] ?? '',
        name: _relative(test['name'] as String),
      );
    }
  }

  void _onError(Map<String, dynamic> event) {
    final running = _running[event['testID']];
    if (running == null) return;
    final error = event['error'];
    if (error is String) running.messages.add(error);
    final stack = event['stackTrace'];
    if (stack is String && stack.isNotEmpty) running.stacks.add(stack);
  }

  void _onTestDone(Map<String, dynamic> event) {
    final running = _running.remove(event['testID']);
    if (running == null) return;
    final result = event['result'];
    // The hidden tests that succeed are the runner's own (loading a file,
    // `setUpAll`): they are no tests of the app.
    if (event['hidden'] == true && result == 'success') return;
    final status = event['skipped'] == true
        ? TestStatus.skipped
        : switch (result) {
            'success' => TestStatus.passed,
            'failure' => TestStatus.failed,
            _ => TestStatus.errored,
          };
    _tests.add(
      TestCase(
        suite: running.suite,
        name: running.name,
        status: status,
        message: _detail(running.messages),
        stackTrace: _detail(running.stacks),
      ),
    );
  }

  String? _detail(List<String> parts) {
    if (parts.isEmpty) return null;
    final text = _relative(parts.join('\n\n'));
    return text.length <= maxTestDetailLength
        ? text
        : '${text.substring(0, maxTestDetailLength)}…';
  }

  /// [text] with the absolute app directory taken out of the paths in it.
  String _relative(String text) => text.replaceAll('$appDirectory/', '');
}

class _RunningTest {
  new({required this.suite, required this.name});

  final String suite;
  final String name;
  final messages = <String>[];
  final stacks = <String>[];
}
