import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

ProcessOutput _ok([String stdout = '', String stderr = '']) =>
    ProcessOutput(exitCode: 0, stdout: stdout, stderr: stderr);

/// Answers the probe commands like a machine that has [has], by command id.
ProcessOutput Function(FakeProcessCall call) _machine(
  String uname,
  Set<String> has,
) => (call) {
  final script = call.arguments.length == 2 ? call.arguments[1] : '';
  final id = switch (call.executable) {
    'uname' => 'os',
    'sh' when script == RunnerProbe.androidSdkScript => 'android_sdk',
    'sh' when script == RunnerProbe.javaScript => 'java',
    'sh' => 'flutter_tools',
    final executable => executable,
  };
  if (id == 'os') return _ok('$uname\n');
  if (!has.contains(id)) {
    return const ProcessOutput(exitCode: 127, stderr: 'not found');
  }
  return switch (id) {
    'java' => _ok('', 'openjdk version "21.0.4" 2024-07-16\n'),
    'xcodebuild' => _ok('Xcode 27.1\nBuild version 27A9275\n'),
    _ => _ok('version 1\n'),
  };
};

void main() {
  test('runs the commands of the runner probe, in order', () async {
    final asked = <String>[];
    final runner = FakeProcessRunner((call) {
      asked.add(call.executable);
      return _machine('Darwin', const {})(call);
    });

    await LocalCapabilities(runner: runner, operatingSystem: 'macos').probe();

    expect(asked, ['uname', 'git', 'sh', 'sh', 'xcode-select']);
  });

  test('a Mac with Xcode, git, a JDK and the Android SDK can do three '
      'things', () async {
    final findings = await LocalCapabilities(
      runner: FakeProcessRunner(
        _machine('Darwin', const {
          'git',
          'android_sdk',
          'java',
          'xcode-select',
          'xcodebuild',
        }),
      ),
      operatingSystem: 'macos',
    ).probe();

    expect(findings.capabilities, {
      Capability.flutter,
      Capability.android,
      Capability.iosSign,
    });
    expect(findings.missing, isEmpty);
  });

  test('a Linux box without a JDK says why it has no android', () async {
    final findings = await LocalCapabilities(
      runner: FakeProcessRunner(
        _machine('Linux', const {'git', 'flutter_tools', 'android_sdk'}),
      ),
      operatingSystem: 'linux',
    ).probe();

    expect(findings.capabilities, {Capability.flutter});
    expect(findings.missing.map((m) => '${m.capability}: ${m.reason}'), [
      'android: no JDK: java not found',
      'swift-linux: no Swift: swift not found',
    ]);
  });
}
