import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import 'fixtures.dart';

ProcessOutput _ok(String stdout) => ProcessOutput(exitCode: 0, stdout: stdout);

/// A runner whose programs answer from [answers], by `executable args`.
FakeProcessRunner _runner(Map<String, ProcessOutput> answers) =>
    FakeProcessRunner((call) {
      final key = [call.executable, ...call.arguments].join(' ');
      return answers[key] ??
          (throw ProcessStartException(call.executable, 'not found'));
    });

final Map<String, ProcessOutput> _machine = {
  'shorebird --version': _ok(fixture('shorebird_version.txt')),
  'gh --version': _ok(fixture('gh_version.txt')),
  'xcode-select -p': _ok(fixture('xcode_select_p.txt')),
  'xcodebuild -version': _ok(fixture('xcodebuild_version.txt')),
};

void main() {
  group('ToolReport', () {
    test('is available only with the status available', () {
      expect(
        const ToolReport('gh', ToolStatus.available, version: '1').isAvailable,
        isTrue,
      );
      for (final status in ToolStatus.values.skip(1)) {
        expect(ToolReport('gh', status).isAvailable, isFalse);
      }
    });

    test('compares by value', () {
      expect(
        const ToolReport('gh', ToolStatus.available, version: '1'),
        const ToolReport('gh', ToolStatus.available, version: '1'),
      );
      expect(
        const ToolReport('gh', ToolStatus.available, version: '1'),
        isNot(const ToolReport('gh', ToolStatus.available, version: '2')),
      );
    });
  });

  group('ToolProber on a Mac', () {
    late FakeProcessRunner runner;
    late ToolProber prober;

    setUp(() {
      runner = _runner(_machine);
      prober = ToolProber(runner: runner, isMacOS: true);
    });

    test('reads the version of every tool', () async {
      expect(await prober.probeAll(), const [
        ToolReport('shorebird', ToolStatus.available, version: '1.6.128'),
        ToolReport('gh', ToolStatus.available, version: '2.96.0'),
        ToolReport(
          'xcode',
          ToolStatus.available,
          version: '27.1',
          detail:
              'build 27A9275, '
              '/Applications/Xcode-27.1.app/Contents/Developer',
        ),
      ]);
    });

    test('runs gh without prompts or colours', () async {
      await prober.gh();

      expect(runner.calls.single.environment, {
        'GH_PROMPT_DISABLED': '1',
        'GH_NO_UPDATE_NOTIFIER': '1',
        'NO_COLOR': '1',
      });
    });

    test('runs the executables it was given', () async {
      final custom = _runner({
        '/opt/sb/shorebird --version': _ok(fixture('shorebird_version.txt')),
        '/opt/gh/gh --version': _ok(fixture('gh_version.txt')),
      });
      final prober = ToolProber(
        runner: custom,
        isMacOS: false,
        shorebirdExecutable: '/opt/sb/shorebird',
        ghExecutable: '/opt/gh/gh',
      );

      expect((await prober.shorebird()).version, '1.6.128');
      expect((await prober.gh()).version, '2.96.0');
    });

    test('reports a tool that is not installed, with the fix', () async {
      final report = await ToolProber(
        runner: _runner({}),
        isMacOS: true,
      ).shorebird();

      expect(report.status, ToolStatus.missing);
      expect(report.version, isNull);
      expect(report.message, contains('shorebird was not found'));
      expect(report.message, contains('https://docs.shorebird.dev'));
    });

    test('reports a tool that exits with an error', () async {
      final report = await ToolProber(
        runner: _runner({
          'gh --version': const ProcessOutput(
            exitCode: 2,
            stderr: 'boom\nsecond line\n',
          ),
        }),
        isMacOS: true,
      ).gh();

      expect(report.status, ToolStatus.failed);
      expect(report.message, contains('exited with 2: boom'));
      expect(report.message, isNot(contains('second line')));
    });

    test('uses stdout when the error went there', () async {
      final report = await ToolProber(
        runner: _runner({
          'gh --version': const ProcessOutput(exitCode: 1, stdout: 'on stdout'),
        }),
        isMacOS: true,
      ).gh();

      expect(report.message, contains('on stdout'));
    });

    test('reports a version it cannot read', () async {
      final report = await ToolProber(
        runner: _runner({'gh --version': _ok('gh: a new thing\nmore\n')}),
        isMacOS: true,
      ).gh();

      expect(report.status, ToolStatus.failed);
      expect(report.message, contains('printed no version I understand'));
      expect(report.message, contains('gh: a new thing'));
    });

    test('reports a tool that does not answer in time', () async {
      final report = await ToolProber(
        runner: FakeProcessRunner((_) => Completer<ProcessOutput>().future),
        isMacOS: true,
        timeout: const Duration(milliseconds: 10),
      ).gh();

      expect(report.status, ToolStatus.failed);
      expect(report.message, 'It did not answer in time.');
    });

    test('does not run xcodebuild when no Xcode is selected', () async {
      final runner = _runner({
        'xcode-select -p': const ProcessOutput(
          exitCode: 2,
          stderr: 'xcode-select: error: unable to get active developer dir',
        ),
        'xcodebuild -version': _ok(fixture('xcodebuild_version.txt')),
      });

      final report = await ToolProber(runner: runner, isMacOS: true).xcode();

      expect(report.status, ToolStatus.failed);
      expect(report.message, contains('unable to get active developer dir'));
      expect(runner.calls.map((c) => c.executable), ['xcode-select']);
    });

    test('reports command line tools without Xcode', () async {
      final report = await ToolProber(
        runner: _runner({
          'xcode-select -p': _ok('/Library/Developer/CommandLineTools\n'),
          'xcodebuild -version': const ProcessOutput(
            exitCode: 1,
            stderr: 'xcode-select: error: tool xcodebuild requires Xcode\n',
          ),
        }),
        isMacOS: true,
      ).xcode();

      expect(report.status, ToolStatus.failed);
      expect(report.message, contains('requires Xcode'));
      expect(report.message, contains('xcode-select -s'));
    });

    test('keeps an Xcode without a build', () async {
      final report = await ToolProber(
        runner: _runner({
          'xcode-select -p': _ok('/X/Developer\n'),
          'xcodebuild -version': _ok('Xcode 16.2\n'),
        }),
        isMacOS: true,
      ).xcode();

      expect(report.version, '16.2');
      expect(report.detail, '/X/Developer');
    });

    test('reports xcode-select that is missing', () async {
      final report = await ToolProber(
        runner: _runner({}),
        isMacOS: true,
      ).xcode();

      expect(report.status, ToolStatus.missing);
    });
  });

  group('ToolProber on Linux', () {
    test('says Xcode is not available, and never looks for it', () async {
      final runner = _runner(_machine);

      final report = await ToolProber(runner: runner, isMacOS: false).xcode();

      expect(report.status, ToolStatus.unsupported);
      expect(report.isAvailable, isFalse);
      expect(
        report.message,
        'Xcode is not available on this operating system.',
      );
      expect(runner.calls, isEmpty);
    });

    test('still reports the other tools', () async {
      final reports = await ToolProber(
        runner: _runner(_machine),
        isMacOS: false,
      ).probeAll();

      expect(reports.map((r) => (r.tool, r.status)), [
        ('shorebird', ToolStatus.available),
        ('gh', ToolStatus.available),
        ('xcode', ToolStatus.unsupported),
      ]);
    });
  });
}
