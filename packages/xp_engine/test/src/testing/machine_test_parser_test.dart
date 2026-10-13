import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/testing_fixtures.dart';

void main() {
  group('the captured run of 27 failing tests', () {
    late ParsedTestRun run;

    setUp(() => run = parseCapturedRun('baseline_27_failures.jsonl'));

    test('reports every test once', () {
      expect(
        run.results.counts,
        const TestCounts(
          total: 48,
          passed: 19,
          failed: 25,
          errored: 2,
          skipped: 2,
        ),
      );
      expect(run.success, isFalse);
    });

    test('identifies tests by file and full name, groups included', () {
      final test =
          run.results[const TestRef(
            suite: 'test/math_test.dart',
            name: 'arithmetic division divides by zero',
          )];

      expect(test?.status, TestStatus.errored);
      expect(test?.message, 'Bad state: division by zero');
    });

    test('keeps the message and the stack of a failed expectation', () {
      final test =
          run.results[const TestRef(
            suite: 'test/async_test.dart',
            name: 'async failure 1',
          )]!;

      expect(test.status, TestStatus.failed);
      expect(test.message, 'Expected: <2>\n  Actual: <1>\n');
      expect(test.stackTrace, contains('test/async_test.dart 8:7'));
    });

    test('keeps unicode names and multi-line messages', () {
      expect(
        run
            .results[const TestRef(
              suite: 'test/strings_test.dart',
              name: 'strings ünïcode ✓ name',
            )]
            ?.status,
        TestStatus.passed,
      );
      expect(
        run
            .results[const TestRef(
              suite: 'test/strings_test.dart',
              name: 'strings multi-line mismatch',
            )]
            ?.message,
        contains('Which: at location [2] is <3> instead of <4>'),
      );
    });

    test('reports skipped tests as skipped, not as passed', () {
      expect(
        run.results.tests
            .where((test) => test.status == TestStatus.skipped)
            .map((test) => test.name),
        ['strings skipped for now', 'strings skipped too'],
      );
    });

    test('leaves out the loading of a file, which is not a test', () {
      expect(
        run.results.tests.where((test) => test.name.startsWith('loading')),
        isEmpty,
      );
    });

    test('has no absolute path of the machine in what it keeps', () {
      for (final test in run.results.tests) {
        expect(test.suite, startsWith('test/'));
        expect('${test.message}${test.stackTrace}', isNot(contains('/work/')));
      }
    });

    test('orders the tests by file and name', () {
      final names = [
        for (final test in run.results.tests) '${test.suite}|${test.name}',
      ];

      expect(names, [...names]..sort());
    });
  });

  group('a run with a file that does not load and a failing setUpAll', () {
    late ParsedTestRun run;

    setUp(() => run = parseCapturedRun('load_and_setup_failures.jsonl'));

    test('counts the runner-made tests that fail', () {
      expect(
        [
          for (final test in run.results.failures)
            '${test.suite} ${test.name} ${test.status.wire}',
        ],
        [
          'test/broken_test.dart loading test/broken_test.dart errored',
          'test/setup_test.dart needs setup (setUpAll) errored',
        ],
      );
    });

    test('keeps the message of the file that does not compile', () {
      final test =
          run.results[const TestRef(
            suite: 'test/broken_test.dart',
            name: 'loading test/broken_test.dart',
          )]!;

      expect(test.message, contains("Undefined name 'undefinedThing'"));
      expect(
        test.message,
        startsWith('Failed to load "test/broken_test.dart"'),
      );
    });

    test('passes the test that does not need the setup', () {
      expect(run.results.counts.passed, 1);
    });
  });

  group('the stream', () {
    late MachineTestParser parser;

    setUp(() => parser = MachineTestParser(appDirectory: '/app'));

    String event(Map<String, dynamic> json) => jsonEncode(json);

    void suite(int id, String path) => parser.addLine(
      event({
        'type': 'suite',
        'suite': {'id': id, 'platform': 'vm', 'path': path},
      }),
    );

    void start(int id, String name, {int suiteId = 0}) => parser.addLine(
      event({
        'type': 'testStart',
        'test': {'id': id, 'name': name, 'suiteID': suiteId},
      }),
    );

    void done(
      int id,
      String result, {
      bool skipped = false,
      bool hidden = false,
    }) => parser.addLine(
      event({
        'type': 'testDone',
        'testID': id,
        'result': result,
        'skipped': skipped,
        'hidden': hidden,
      }),
    );

    test('is not a run before the done event', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'works');
      done(1, 'success');

      expect(parser.finish(), isNull);
      expect(parser.events, 3);
    });

    test('ignores lines that are not JSON objects', () {
      [
        '',
        'Resolving dependencies...',
        '[{"event":"test.startedProcess","params":{"vmServiceUri":null}}]',
        '{"truncated":',
        '{"no":"type"}',
        '{"type":7}',
        '"a string"',
        '{ }',
      ].forEach(parser.addLine);

      expect(parser.events, 0);
      expect(parser.finish(), isNull);
    });

    test('reads the success of the done event', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'works');
      done(1, 'success');
      parser.addLine(event({'type': 'done', 'success': true}));

      final run = parser.finish()!;

      expect(run.success, isTrue);
      expect(run.results.counts.passed, 1);
    });

    test('does not count a hidden test that succeeds', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'loading /app/test/a_test.dart');
      done(1, 'success', hidden: true);
      parser.addLine(event({'type': 'done', 'success': true}));

      expect(parser.finish()!.results.tests, isEmpty);
    });

    test('counts a hidden test that fails', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'loading /app/test/a_test.dart');
      done(1, 'error', hidden: true);
      parser.addLine(event({'type': 'done', 'success': false}));

      expect(parser.finish()!.results.tests.single.status, TestStatus.errored);
    });

    test('names a test of an unknown suite by its name alone', () {
      start(1, 'orphan', suiteId: 9);
      done(1, 'failure');
      parser.addLine(event({'type': 'done', 'success': false}));

      final test = parser.finish()!.results.tests.single;

      expect(test.suite, '');
      expect(test.status, TestStatus.failed);
    });

    test('keeps a path outside the app as it is', () {
      suite(0, '/elsewhere/a_test.dart');
      start(1, 'works');
      done(1, 'success');
      parser.addLine(event({'type': 'done', 'success': true}));

      expect(
        parser.finish()!.results.tests.single.suite,
        '/elsewhere/a_test.dart',
      );
    });

    test('skips events it cannot place', () {
      parser
        ..addLine(event({'type': 'suite', 'suite': 'nope'}))
        ..addLine(
          event({
            'type': 'suite',
            'suite': {'id': 'x', 'path': 1},
          }),
        )
        ..addLine(event({'type': 'testStart', 'test': 'nope'}))
        ..addLine(
          event({
            'type': 'testStart',
            'test': {'id': 'x'},
          }),
        )
        ..addLine(event({'type': 'error', 'testID': 99, 'error': 'e'}))
        ..addLine(
          event({'type': 'testDone', 'testID': 99, 'result': 'success'}),
        )
        ..addLine(event({'type': 'print', 'testID': 1, 'message': 'hi'}))
        ..addLine(event({'type': 'done', 'success': true}));

      expect(parser.finish()!.results.tests, isEmpty);
    });

    test('takes an unknown result for an error', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'odd');
      done(1, 'weird');
      parser.addLine(event({'type': 'done', 'success': false}));

      expect(parser.finish()!.results.tests.single.status, TestStatus.errored);
    });

    test('joins the errors a test reported and ignores empty ones', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'odd');
      parser
        ..addLine(
          event({'type': 'error', 'testID': 1, 'error': 4, 'stackTrace': ''}),
        )
        ..addLine(
          event({
            'type': 'error',
            'testID': 1,
            'error': 'boom',
            'stackTrace': 'at /app/lib/a.dart 1:1',
          }),
        )
        ..addLine(event({'type': 'error', 'testID': 1, 'error': 'then this'}));
      done(1, 'failure');
      parser.addLine(event({'type': 'done', 'success': false}));

      final test = parser.finish()!.results.tests.single;

      expect(test.message, 'boom\n\nthen this');
      expect(test.stackTrace, 'at lib/a.dart 1:1');
    });

    test('cuts a message that is too long', () {
      suite(0, '/app/test/a_test.dart');
      start(1, 'verbose');
      parser.addLine(
        event({
          'type': 'error',
          'testID': 1,
          'error': 'x' * (maxTestDetailLength + 50),
        }),
      );
      done(1, 'failure');
      parser.addLine(event({'type': 'done', 'success': false}));

      final message = parser.finish()!.results.tests.single.message!;

      expect(message, hasLength(maxTestDetailLength + 1));
      expect(message, endsWith('…'));
    });
  });
}
