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
        'flutter_tools',
        'android_sdk',
        'java',
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
          'sh -c',
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
      expect(byId['flutter_tools']!.onlyOn, 'linux');
      expect(byId['git']!.onlyOn, isNull);
      expect(byId['java']!.onlyOn, isNull);
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

    test('the JDK script looks where Flutter looks', () {
      for (final place in const [
        r'$JAVA_HOME/bin/java',
        'Android Studio.app/Contents/jbr',
        'android-studio/jbr',
        'exec java -version',
      ]) {
        expect(RunnerProbe.javaScript, contains(place));
      }
      for (final tool in const ['curl', 'unzip', 'xz']) {
        expect(RunnerProbe.flutterToolsScript, contains(tool));
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

    test('Linux needs curl, unzip and xz for flutter', () {
      final findings = probe.evaluate([
        ...linuxProbe().where((r) => r.id != 'flutter_tools'),
        exited('flutter_tools', code: 1, stdout: 'unzip xz\n'),
      ]);

      expect(findings.capabilities, {Capability.android});
      expect(
        findings.missing.first,
        const MissingCapability(
          capability: 'flutter',
          reason: 'no unzip, xz: the Flutter SDK download needs them',
          fix: 'install them (apt-get install unzip xz-utils)',
        ),
      );
    });

    test('a JDK older than 17 or without a version does not count', () {
      List<ProbeResult> withJava(ProbeResult java) => [
        ...linuxProbe().where((r) => r.id != 'java'),
        java,
      ];

      for (final (java, reason) in [
        (javaProbe(11), 'no JDK: JDK 11 is older than 17'),
        (
          const ProbeResult(
            id: 'java',
            status: ProbeStatus.exited,
            exitCode: 0,
            stderr: 'java version "1.8.0_381"',
          ),
          'no JDK: JDK 8 is older than 17',
        ),
        (exited('java'), 'no JDK: java printed no version'),
      ]) {
        final findings = probe.evaluate(withJava(java));
        expect(findings.capabilities, {Capability.flutter});
        expect(findings.missing.first.reason, reason);
      }
      expect(
        probe.evaluate(withJava(javaProbe(21))).capabilities,
        contains(Capability.android),
      );
    });

    group('missing', () {
      String describe(List<ProbeResult> results) => probe
          .evaluate(results)
          .missing
          .map((m) => '${m.capability}: ${m.explanation}')
          .join('\n');

      test('a Linux box without a JDK, swift or an SDK says why', () {
        expect(
          describe([
            ...linuxProbe(android: false).where((r) => r.id != 'java'),
            exited('java', code: 127),
          ]),
          'android: no Android SDK in ANDROID_HOME, ANDROID_SDK_ROOT or '
          '~/Android/Sdk. Install the Android command-line tools or set '
          'ANDROID_HOME.\n'
          'android: no JDK: java not found. Install JDK 17 (apt-get install '
          'openjdk-17-jdk-headless) or set JAVA_HOME.\n'
          'swift-linux: no Swift: swift not found. Install Swift for Linux '
          'from swift.org.',
        );
      });

      test('a Mac never lists swift-linux, and says why it cannot sign', () {
        expect(
          describe(macProbe(xcode: false, android: true)),
          'ios-sign: no Xcode selected: xcode-select not found. Install '
          'Xcode and choose it in Xcode, Settings, Locations, Command Line '
          'Tools.',
        );
        expect(
          describe([
            ...macProbe(android: true).where((r) => r.id != 'xcodebuild'),
            const ProbeResult(
              id: 'xcodebuild',
              status: ProbeStatus.exited,
              exitCode: 69,
              stderr: 'You have not agreed to the Xcode license agreements.\n',
            ),
          ]),
          'ios-sign: Xcode does not answer: You have not agreed to the Xcode '
          'license agreements. Open Xcode once to finish its setup and '
          'accept its licence.',
        );
      });

      test('the reason comes from the result that failed', () {
        String gitReason(ProbeResult git) =>
            probe.evaluate([git]).missing.first.reason;

        expect(
          gitReason(
            const ProbeResult(id: 'git', status: ProbeStatus.notStarted),
          ),
          'no git: git not found',
        );
        expect(
          gitReason(const ProbeResult(id: 'git', status: ProbeStatus.timedOut)),
          'no git: git did not answer in time',
        );
        expect(
          gitReason(const ProbeResult(id: 'git', status: ProbeStatus.skipped)),
          'no git: git was not checked',
        );
        expect(
          gitReason(
            const ProbeResult(
              id: 'git',
              status: ProbeStatus.exited,
              exitCode: 1,
              stderr: '\n  xcrun: error: invalid active developer path\nmore',
            ),
          ),
          'no git: xcrun: error: invalid active developer path',
        );
        expect(
          gitReason(exited('git', code: 2, stdout: 'odd\n')),
          'no git: odd',
        );
        expect(gitReason(exited('git', code: 3)), 'no git: git exited with 3');
        expect(probe.evaluate(const []).missing.first.fix, 'install git');
      });

      test('a failed check of the Linux tools says so', () {
        final findings = probe.evaluate([
          ...linuxProbe().where((r) => r.id != 'flutter_tools'),
          const ProbeResult(id: 'flutter_tools', status: ProbeStatus.timedOut),
        ]);

        expect(
          findings.missing.first.explanation,
          'no curl, unzip or xz: they could not be checked (sh did not answer '
          'in time). '
          'Install them (apt-get install curl unzip xz-utils).',
        );
        expect(
          probe
              .evaluate([
                ...linuxProbe().where((r) => r.id != 'flutter_tools'),
                exited('flutter_tools', code: 1, stdout: 'curl\n'),
              ])
              .missing
              .first
              .fix,
          'install it (apt-get install curl)',
        );
      });

      test('an Xcode that prints no version cannot sign', () {
        expect(
          probe
              .evaluate([
                exited('os', stdout: 'Darwin'),
                exited('xcode_select', stdout: '/x'),
                exited('xcodebuild', stdout: 'nothing useful'),
              ])
              .missing
              .last
              .reason,
          'Xcode does not answer: xcodebuild printed no Xcode version',
        );
      });
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
