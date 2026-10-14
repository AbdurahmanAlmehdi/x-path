import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

void main() {
  const probe = RunnerProbe();

  ProbeResult exited(String id, {int code = 0, String stdout = ''}) =>
      ProbeResult(
        id: id,
        status: ProbeStatus.exited,
        exitCode: code,
        stdout: stdout,
      );

  group('commands', () {
    test('only ask for versions and look for folders', () {
      expect(probe.commands.map((c) => c.id), [
        'os',
        'git',
        'android_sdk',
        'xcode_select',
        'xcodebuild',
        'swift',
      ]);
      expect(
        probe.commands.map((c) => '${c.executable} ${c.arguments.first}'),
        [
          'uname -s',
          'git --version',
          'sh -c',
          'xcode-select -p',
          'xcodebuild -version',
          'swift --version',
        ],
      );
    });

    test('keep xcodebuild and swift away from a machine without them', () {
      final byId = {for (final c in probe.commands) c.id: c};

      expect(byId['xcode_select']!.onlyOn, 'macos');
      expect(byId['xcodebuild']!.onlyOn, 'macos');
      expect(byId['xcodebuild']!.requires, 'xcode_select');
      expect(byId['swift']!.onlyOn, 'linux');
      expect(byId['git']!.onlyOn, isNull);
    });

    test('the Android script looks where the engine looks', () {
      for (final place in const [
        r'$ANDROID_HOME',
        r'$ANDROID_SDK_ROOT',
        r'$HOME/Library/Android/sdk',
        r'$HOME/Android/Sdk',
        'platform-tools',
        'cmdline-tools',
        'build-tools',
      ]) {
        expect(RunnerProbe.androidSdkScript, contains(place));
      }
    });

    test('are the same every time', () {
      expect(probe.commands, probe.commands);
    });
  });

  group('evaluate', () {
    test('a Mac with Xcode can sign and build Flutter', () {
      final findings = probe.evaluate(macProbe());

      expect(findings.operatingSystem, 'macos');
      expect(findings.capabilities, {Capability.flutter, Capability.iosSign});
    });

    test('a Mac with an Android SDK builds Android too', () {
      expect(probe.evaluate(macProbe(android: true)).capabilities, {
        Capability.flutter,
        Capability.android,
        Capability.iosSign,
      });
    });

    test('a Mac without Xcode cannot sign', () {
      expect(probe.evaluate(macProbe(xcode: false)).capabilities, {
        Capability.flutter,
      });
    });

    test('Xcode counts when it prints a version', () {
      expect(
        probe.evaluate([
          exited('os', stdout: 'Darwin'),
          exited('xcode_select', stdout: '/x'),
          exited('xcodebuild', stdout: 'xcode-select: error: no Xcode'),
        ]).capabilities,
        isEmpty,
      );
      expect(
        probe.evaluate([
          exited('os', stdout: 'Darwin'),
          exited('xcode_select', stdout: '/x'),
          exited('xcodebuild', code: 1, stdout: 'Xcode 26.1'),
        ]).capabilities,
        isEmpty,
      );
    });

    test('Linux builds Android and Swift, and cannot sign', () {
      final findings = probe.evaluate(linuxProbe(swift: true));

      expect(findings.operatingSystem, 'linux');
      expect(findings.capabilities, {
        Capability.flutter,
        Capability.android,
        Capability.swiftLinux,
      });
      expect(probe.evaluate(linuxProbe(android: false)).capabilities, {
        Capability.flutter,
      });
    });

    test(
      'swift on a Mac is not swift-linux, and Xcode on Linux is no Xcode',
      () {
        expect(
          probe.evaluate([
            exited('os', stdout: 'Darwin'),
            exited('swift', stdout: 'Swift version 6'),
          ]).capabilities,
          isEmpty,
        );
        expect(
          probe.evaluate([
            exited('os', stdout: 'Linux'),
            exited('xcode_select', stdout: '/x'),
            exited('xcodebuild', stdout: 'Xcode 26.1'),
          ]).capabilities,
          isEmpty,
        );
      },
    );

    test('says nothing for what did not run or did not answer', () {
      for (final results in <List<ProbeResult>>[
        const [],
        [exited('os', code: 1, stdout: 'Darwin'), exited('swift')],
        [exited('os', stdout: 'FreeBSD'), exited('swift')],
        const [ProbeResult(id: 'git', status: ProbeStatus.timedOut)],
        const [ProbeResult(id: 'git', status: ProbeStatus.notStarted)],
        const [ProbeResult(id: 'git', status: ProbeStatus.skipped)],
        [exited('git', code: 127)],
      ]) {
        final findings = probe.evaluate(results);
        expect(findings.capabilities.contains(Capability.iosSign), isFalse);
        expect(findings.capabilities.contains(Capability.swiftLinux), isFalse);
        expect(findings.capabilities.contains(Capability.flutter), isFalse);
      }
      expect(
        probe.evaluate([exited('os', stdout: 'FreeBSD')]).operatingSystem,
        isNull,
      );
    });

    test('ignores what it did not ask', () {
      final findings = probe.evaluate([
        ...macProbe(),
        exited('ios-sign'),
        exited('claims', stdout: 'android'),
      ]);

      expect(findings.capabilities, {Capability.flutter, Capability.iosSign});
    });

    test('findings compare by value', () {
      final capabilities = {Capability.flutter};

      expect(
        ProbeFindings(capabilities: capabilities, operatingSystem: 'linux'),
        ProbeFindings(
          capabilities: {...capabilities},
          operatingSystem: 'linux',
        ),
      );
    });
  });
}
