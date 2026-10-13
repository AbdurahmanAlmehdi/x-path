import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';

/// How bad a status is, to pick one when a test name occurs twice in a file.
int _severity(TestStatus status) => switch (status) {
  TestStatus.errored => 3,
  TestStatus.failed => 2,
  TestStatus.passed => 1,
  TestStatus.skipped => 0,
};

int _byIdentity(TestCase a, TestCase b) {
  final bySuite = a.suite.compareTo(b.suite);
  return bySuite != 0 ? bySuite : a.name.compareTo(b.name);
}

/// Every test of one `flutter test` run, by identity (D-21).
///
/// A test is identified by its file and its full name. Two tests of a file
/// with the same full name count as one, and the worse outcome wins, so that a
/// failure is never hidden.
class TestRunResults extends Equatable {
  /// Collects [tests], ordered by file and name.
  factory of(Iterable<TestCase> tests) {
    final byRef = <TestRef, TestCase>{};
    for (final test in tests) {
      final known = byRef[test.ref];
      if (known == null || _severity(test.status) > _severity(known.status)) {
        byRef[test.ref] = test;
      }
    }
    return ._(byRef, byRef.values.toList()..sort(_byIdentity));
  }

  /// Reads the results from the compact form [toJson] writes.
  ///
  /// Throws a [FormatException] if [json] is not valid.
  factory fromJson(Map<String, dynamic> json) {
    final suites = requiredObject(json, 'suites');
    final tests = <TestCase>[];
    for (final MapEntry(key: suite, value: group) in suites.entries) {
      if (group is! Map<String, dynamic>) {
        throw FormatException('"suites.$suite" must be an object.');
      }
      for (final status in TestStatus.values) {
        final entries = group[status.wire];
        if (entries == null) continue;
        if (entries is! List) {
          throw FormatException(
            '"suites.$suite.${status.wire}" must be a list.',
          );
        }
        for (final entry in entries) {
          tests.add(_testOf(suite, status, entry));
        }
      }
    }
    return TestRunResults.of(tests);
  }

  const new _(this._byRef, this.tests);

  static TestCase _testOf(String suite, TestStatus status, Object? entry) {
    if (status.isFailure && entry is Map<String, dynamic>) {
      return TestCase(
        suite: suite,
        name: requiredString(entry, 'name'),
        status: status,
        message: optionalString(entry, 'message'),
        stackTrace: optionalString(entry, 'stackTrace'),
      );
    }
    if (!status.isFailure && entry is String) {
      return TestCase(suite: suite, name: entry, status: status);
    }
    throw FormatException('"suites.$suite.${status.wire}" has a bad entry.');
  }

  final Map<TestRef, TestCase> _byRef;

  /// The tests, ordered by file and name.
  final List<TestCase> tests;

  /// The test with identity [ref], or `null` if the run did not report it.
  TestCase? operator [](TestRef ref) => _byRef[ref];

  /// The files the run reported tests of.
  Set<String> get suites => {for (final test in tests) test.suite};

  /// The tests that failed or threw.
  Iterable<TestCase> get failures =>
      tests.where((test) => test.status.isFailure);

  /// How many tests ended each way.
  TestCounts get counts {
    int of(TestStatus status) =>
        tests.where((test) => test.status == status).length;
    return TestCounts(
      total: tests.length,
      passed: of(TestStatus.passed),
      failed: of(TestStatus.failed),
      errored: of(TestStatus.errored),
      skipped: of(TestStatus.skipped),
    );
  }

  /// The compact stored form: per file, the names that passed or were skipped
  /// and the failures with their message and stack trace. A run of thousands
  /// of tests stays small because a passing test costs its name only.
  Map<String, dynamic> toJson() {
    final suites = <String, Map<String, List<Object>>>{};
    for (final test in tests) {
      final group = suites.putIfAbsent(test.suite, () => {});
      group
          .putIfAbsent(test.status.wire, () => [])
          .add(
            test.status.isFailure
                ? {
                    'name': test.name,
                    'message': ?test.message,
                    'stackTrace': ?test.stackTrace,
                  }
                : test.name,
          );
    }
    return {'suites': suites};
  }

  @override
  List<Object?> get props => [tests];
}
