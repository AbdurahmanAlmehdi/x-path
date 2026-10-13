import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/testing_fixtures.dart';

AnalyzeReport? _read(List<String> lines) {
  final parser = AnalyzeOutputParser();
  lines.forEach(parser.addLine);
  return parser.finish();
}

void main() {
  group('AnalyzeOutputParser', () {
    test('reads the captured output of flutter analyze', () {
      final report = _read(fixtureLines('analyze_issues.txt'))!;

      expect(report.reported, 4);
      expect(report.complete, isTrue);
      expect(report.issues, [
        const AnalyzeIssue(
          severity: AnalyzeSeverity.warning,
          message:
              "The value of the local variable 'unused' isn't used. Try "
              'removing the variable or using it',
          path: 'lib/main.dart',
          line: 5,
          column: 7,
          code: 'unused_local_variable',
        ),
        const AnalyzeIssue(
          severity: AnalyzeSeverity.error,
          message:
              "Undefined name 'undefinedName'. Try correcting the name to one "
              'that is defined, or defining the name',
          path: 'lib/main.dart',
          line: 6,
          column: 10,
          code: 'undefined_identifier',
        ),
        const AnalyzeIssue(
          severity: AnalyzeSeverity.info,
          message:
              "Don't invoke 'print' in production code. Try using a logging "
              'framework',
          path: 'lib/main.dart',
          line: 12,
          column: 17,
          code: 'avoid_print',
        ),
        const AnalyzeIssue(
          severity: AnalyzeSeverity.error,
          message:
              "A value of type 'int' can't be returned from the function "
              "'takesInt' because it has a return type of 'String'",
          path: 'lib/main.dart',
          line: 15,
          column: 27,
          code: 'return_of_invalid_type',
        ),
      ]);
      expect(report.count(AnalyzeSeverity.error), 2);
      expect(report.count(AnalyzeSeverity.warning), 1);
      expect(report.count(AnalyzeSeverity.info), 1);
    });

    test('reads a clean run', () {
      final report = _read(fixtureLines('analyze_clean.txt'))!;

      expect(report.issues, isEmpty);
      expect(report.reported, 0);
      expect(report.complete, isTrue);
    });

    test('reads the summary of a single issue', () {
      expect(_read(['1 issue found. (ran in 1.0s)'])?.reported, 1);
    });

    test('has no report before the summary', () {
      expect(
        _read(fixtureLines('analyze_issues.txt').take(5).toList()),
        isNull,
      );
      expect(_read(const []), isNull);
    });

    test('knows an issue it could not read is missing', () {
      final report = _read([
        'error • An issue without a place • weird',
        '1 issue found. (ran in 1.0s)',
      ])!;

      expect(report.issues, isEmpty);
      expect(report.complete, isFalse);
    });

    test('keeps a bullet inside the message', () {
      final report = _read([
        '  error • a • b • c • lib/x.dart:1:2 • some_rule',
        '1 issue found.',
      ])!;

      expect(report.issues.single.message, 'a • b • c');
      expect(report.issues.single.location, 'lib/x.dart:1:2');
    });
  });

  group('AnalyzeSeverity', () {
    test('is named by what the analyzer prints', () {
      expect(AnalyzeSeverity.named('warning'), AnalyzeSeverity.warning);
      expect(AnalyzeSeverity.named('hint'), isNull);
      expect(AnalyzeSeverity.named(null), isNull);
    });
  });

  group('AnalyzeResult', () {
    AnalyzeIssue issue(AnalyzeSeverity severity, int line) => AnalyzeIssue(
      severity: severity,
      message: 'm',
      path: 'lib/a.dart',
      line: line,
      column: 1,
      code: 'c',
    );

    test('counts by severity and puts the worst first', () {
      final result = AnalyzeResult.of(
        AnalyzeReport(
          issues: [
            issue(AnalyzeSeverity.info, 1),
            issue(AnalyzeSeverity.error, 2),
            issue(AnalyzeSeverity.warning, 3),
            issue(AnalyzeSeverity.error, 4),
          ],
          reported: 4,
        ),
      );

      expect([for (final i in result.issues) i.line], [2, 4, 3, 1]);
      expect((result.errors, result.warnings, result.infos), (2, 1, 1));
      expect(result.truncated, isFalse);
      expect(result.toJson()['issues'], hasLength(4));
      expect(result.toJson()['truncated'], isFalse);
    });

    test('keeps a bounded number of issues', () {
      final result = AnalyzeResult.of(
        AnalyzeReport(
          issues: [
            for (var i = 0; i < AnalyzeResult.maxStoredIssues + 30; i++)
              issue(AnalyzeSeverity.info, i),
          ],
          reported: AnalyzeResult.maxStoredIssues + 30,
        ),
      );

      expect(result.issues, hasLength(AnalyzeResult.maxStoredIssues));
      expect(result.infos, AnalyzeResult.maxStoredIssues + 30);
      expect(result.truncated, isTrue);
      expect(result.toJson()['truncated'], isTrue);
    });

    test('serializes an issue', () {
      expect(issue(AnalyzeSeverity.error, 7).toJson(), {
        'severity': 'error',
        'message': 'm',
        'path': 'lib/a.dart',
        'line': 7,
        'column': 1,
        'code': 'c',
      });
    });
  });
}
