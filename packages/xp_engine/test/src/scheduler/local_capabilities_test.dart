import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

ProcessOutput _ok([String stdout = '']) =>
    ProcessOutput(exitCode: 0, stdout: stdout);

LocalCapabilities _probe(
  ProcessOutput Function(FakeProcessCall call) answer, {
  bool isMacOS = false,
  String? sdk,
}) {
  final runner = FakeProcessRunner(answer);
  return LocalCapabilities(
    runner: runner,
    prober: ToolProber(runner: runner, isMacOS: isMacOS),
    android: FakeAndroidSdkLocator(sdk),
    isMacOS: isMacOS,
  );
}

void main() {
  test(
    'a Mac with Xcode, git and the Android SDK can do three things',
    () async {
      final capabilities = _probe(
        (call) => switch (call.executable) {
          'xcode-select' => _ok('/Xcode/Developer\n'),
          'xcodebuild' => _ok('Xcode 27.1\nBuild version 27A9275\n'),
          _ => _ok('git version 2.50.1'),
        },
        isMacOS: true,
        sdk: '/sdk',
      );

      expect(await capabilities.probe(), {
        Capability.flutter,
        Capability.android,
        Capability.iosSign,
      });
    },
  );

  test('a Mac never asks for swift', () async {
    final asked = <String>[];
    final capabilities = _probe((call) {
      asked.add(call.executable);
      return _ok('Xcode 27.1\n');
    }, isMacOS: true);

    await capabilities.probe();

    expect(asked, isNot(contains('swift')));
  });

  test('Linux has no ios-sign, and swift-linux when swift runs', () async {
    final capabilities = _probe((call) => _ok('version 1'), sdk: '/sdk');

    expect(await capabilities.probe(), {
      Capability.flutter,
      Capability.android,
      Capability.swiftLinux,
    });
  });

  test('a machine without the tools can do nothing', () async {
    final capabilities = _probe(
      (call) => throw ProcessStartException(call.executable, 'not found'),
    );

    expect(await capabilities.probe(), isEmpty);
  });

  test('a tool that fails or is too slow does not count', () async {
    final failing = _probe(
      (call) => const ProcessOutput(exitCode: 1, stderr: 'broken'),
    );
    final slow = _probe((call) => throw TimeoutException('slow'));

    expect(await failing.probe(), isEmpty);
    expect(await slow.probe(), isEmpty);
  });

  test('a machine without an Xcode selected cannot sign', () async {
    final capabilities = _probe(
      (call) => call.executable == 'xcode-select'
          ? const ProcessOutput(exitCode: 2, stderr: 'no developer tools')
          : _ok('git version 2'),
      isMacOS: true,
    );

    expect(await capabilities.probe(), {Capability.flutter});
  });

  test('the fake locator finds what it was given', () async {
    expect(await const FakeAndroidSdkLocator('/sdk').locate(), '/sdk');
    expect(await const FakeAndroidSdkLocator().locate(), isNull);
  });
}
