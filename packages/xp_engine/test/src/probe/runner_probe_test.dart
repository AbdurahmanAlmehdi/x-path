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

    test('give swift less time, so a slow one does not hold up the engine', () {
      final byId = {for (final c in probe.commands) c.id: c};

      expect(byId['swift']!.timeoutSeconds, 10);
      expect(byId['git']!.timeoutSeconds, 30);
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

    test('Xcode counts only when it exits cleanly with a version', () {
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

    group('ios-linux', () {
      const dir = '/home/me/omarchy-apple-dev';
      const pin = RunnerProbe.iosLinuxPin;
      const setup = 'run install-toolchain.sh in $dir';

      ProbeFindings evaluate(List<ProbeResult> extra, {bool swift = true}) =>
          probe.evaluate([
            ...linuxProbe(swift: swift),
            ...extra,
          ], iosLinuxDirectory: dir);

      List<(String, String)> missing(ProbeFindings findings) => [
        for (final m in findings.missing)
          if (m.capability == 'ios-linux') (m.reason, m.fix),
      ];

      test('has three commands for the folder, Linux only', () {
        final commands = probe.iosLinuxCommands(dir);

        expect(commands.map((c) => c.id), [
          'ios_linux_commit',
          'ios_linux_sdk',
          'ios_linux_tools',
        ]);
        expect(commands.first.executable, 'git');
        expect(commands.first.arguments, ['-C', dir, 'rev-parse', 'HEAD']);
        expect(commands.map((c) => c.onlyOn).toSet(), {'linux'});
        for (final command in commands.skip(1)) {
          expect(command.arguments.last, isNot(contains(dir)));
        }
      });

      test('is offered by a configured Linux runner with everything', () {
        final findings = evaluate(iosLinuxProbe());

        expect(findings.capabilities, contains(Capability.iosLinux));
        expect(missing(findings), isEmpty);
      });

      test('is neither offered nor missing unconfigured or off Linux', () {
        final unconfigured = probe.evaluate([
          ...linuxProbe(swift: true),
          ...iosLinuxProbe(),
        ]);
        final mac = probe.evaluate([
          ...macProbe(),
          ...iosLinuxProbe(),
        ], iosLinuxDirectory: dir);

        for (final findings in [unconfigured, mac]) {
          expect(findings.capabilities, isNot(contains(Capability.iosLinux)));
          expect(missing(findings), isEmpty);
        }
      });

      test('a checkout at another commit says how to move it', () {
        final findings = evaluate(
          iosLinuxProbe(commit: '0123456789abcdef0123456789abcdef01234567'),
        );

        expect(findings.capabilities, isNot(contains(Capability.iosLinux)));
        expect(missing(findings), [
          (
            'omarchy-apple-dev is at 0123456789ab; this XPath needs '
                '79bda716bf20',
            'git -C $dir fetch ${RunnerProbe.iosLinuxRepository} $pin && '
                'git -C $dir checkout $pin',
          ),
        ]);
      });

      test('a folder that is no checkout says how to make one', () {
        final findings = evaluate([
          const ProbeResult(
            id: 'ios_linux_commit',
            status: ProbeStatus.exited,
            exitCode: 128,
            stderr: 'fatal: not a git repository\n',
          ),
          ...iosLinuxProbe().skip(1),
        ]);

        expect(missing(findings), [
          (
            '$dir is not an omarchy-apple-dev checkout: fatal: not a git '
                'repository',
            'git clone ${RunnerProbe.iosLinuxRepository} '
                '$dir && git -C $dir checkout $pin',
          ),
        ]);
      });

      test('lists every missing piece with its fix', () {
        final findings = evaluate([
          const ProbeResult(
            id: 'ios_linux_commit',
            status: ProbeStatus.exited,
            exitCode: 0,
          ),
          ...iosLinuxProbe(
            sdk: false,
            missingTools: 'rcodesign llvm-lipo pymobile3 other',
          ).skip(1),
        ], swift: false);

        expect(missing(findings), [
          (
            'omarchy-apple-dev is at nothing; this XPath needs 79bda716bf20',
            'git -C $dir fetch ${RunnerProbe.iosLinuxRepository} $pin && '
                'git -C $dir checkout $pin',
          ),
          ('no Swift: swift not found', setup),
          (
            'no darwin SDK bundle (swift-sdks/darwin.artifactbundle under '
                r'$XDG_CONFIG_HOME/swiftpm or ~/.swiftpm)',
            'download Xcode.xip in a browser and $setup, as the user the '
                'runner runs as',
          ),
          (
            'no rcodesign, llvm-lipo, ~/pymobile3-venv/bin/python: '
                'omarchy-apple-dev needs them',
            setup,
          ),
        ]);
      });

      test('takes only an absolute folder without control characters', () {
        for (final folder in ['omarchy', '/srv/omar\nchy', '']) {
          final findings = probe.evaluate([
            ...linuxProbe(swift: true),
            ...iosLinuxProbe(),
          ], iosLinuxDirectory: folder);

          expect(findings.capabilities, isNot(contains(Capability.iosLinux)));
          expect(missing(findings), [
            (
              'XP_IOS_LINUX_DIR is not an absolute path of a folder',
              'set XP_IOS_LINUX_DIR to the absolute path of the '
                  'omarchy-apple-dev checkout',
            ),
          ], reason: folder);
        }
      });

      test('quotes a folder with spaces in the commands it gives', () {
        final findings = probe.evaluate([
          ...linuxProbe(swift: true),
          ...iosLinuxProbe(commit: 'f' * 40, missingTools: 'llvm-ar'),
        ], iosLinuxDirectory: "/srv/apple dev's");

        const quoted = r"'/srv/apple dev'\''s'";
        expect(missing(findings), [
          (
            'omarchy-apple-dev is at ffffffffffff; this XPath needs '
                '79bda716bf20',
            'git -C $quoted fetch ${RunnerProbe.iosLinuxRepository} $pin && '
                'git -C $quoted checkout $pin',
          ),
          (
            'no llvm-ar: omarchy-apple-dev needs it',
            'run install-toolchain.sh in $quoted',
          ),
        ]);
      });

      test('one missing tool is it, and tools not checked say so', () {
        expect(missing(evaluate(iosLinuxProbe(missingTools: 'llvm-ar'))), [
          ('no llvm-ar: omarchy-apple-dev needs it', setup),
        ]);
        expect(missing(evaluate(iosLinuxProbe().take(2).toList())), [
          (
            'the Linux iOS tools could not be checked (sh was not checked)',
            setup,
          ),
        ]);
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
