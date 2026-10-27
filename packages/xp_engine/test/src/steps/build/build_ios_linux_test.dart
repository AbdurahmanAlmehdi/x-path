import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

const _checkout = '/opt/omarchy-apple-dev';
const _flutter = '/data/toolchains/flutter/3.47.6';
const _ipa = '$appDirectory/build/ios-linux/Runner-store.ipa';
const _signing = {
  'ASC_SIGNING_KEY': 'identity',
  'ASC_SIGNING_CERT': 'identity.certificate',
  'ASC_PROFILE': 'identity.profile:ly.mataa',
};

/// The checkout of a Linux runner, on fakes: the installs that setup.sh has
/// prepared, and what was marked used.
class _Checkout implements IosLinuxToolchain {
  final prepared = <String>{};
  final used = <String>[];
  String? at = '2d03f766859e6e4549b949b4afbb8e66d851b18d';

  @override
  String get directory => _checkout;

  @override
  String get installs => '/data/toolchains/flutter';

  @override
  Future<String?> commit() async => at;

  @override
  Future<bool> isPrepared(String flutterRoot) async =>
      prepared.contains(flutterRoot);

  @override
  Future<void> markUsed(String flutterRoot) async => used.add(flutterRoot);
}

void main() {
  late BuildHarness harness;
  late _Checkout checkout;
  late BuildIosStep step;
  late BuildContext context;

  BuildIosInput input({
    String? flavor,
    String? target,
    String? dartDefineFile,
    bool obfuscate = false,
    Map<String, String> signing = _signing,
  }) => BuildIosInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: flavor,
      target: target,
      flutterVersion: '3.47.6',
      dartDefineFile: dartDefineFile,
      obfuscate: obfuscate,
    ),
    exportOptionsPlist: 'ios/ExportOptions.plist',
    linuxSigning: signing,
  );

  /// The commands of the run, as `script KEY=value...`, for short checks.
  List<String> scripts() => [
    for (final command in context.commands) command.executable.split('/').last,
  ];

  ProcessCommand named(String script) => context.commands.singleWhere(
    (command) => command.executable == '$_checkout/flutter/$script',
  );

  setUp(() async {
    harness = BuildHarness();
    await harness.createJob();
    checkout = _Checkout()..prepared.add(_flutter);
    step = BuildIosStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
      isMacOS: false,
      linux: IosLinuxBuilds(toolchain: harness.toolchain, checkout: checkout),
    );
    context = BuildContext(
      onRun: (command) {
        if (command.executable.endsWith('/ship.sh')) harness.files.put(_ipa);
        if (command.executable.endsWith('/setup.sh')) {
          checkout.prepared.add(_flutter);
        }
      },
    );
  });

  test('builds with build.sh, signs with ship.sh and stores the IPA', () async {
    final outcome = await step.run(input(), context);

    final result = (outcome as StepSucceeded<BuildResult>).result;
    expect(result.artifact.name, 'app-1.2.3+45.ipa');
    expect(result.flutter, '3.47.6');
    expect(scripts(), ['build.sh', 'ship.sh']);
    final build = named('build.sh');
    expect(build.arguments, [appDirectory]);
    expect(build.workingDirectory, appDirectory);
    expect(build.environment, {
      'CI': 'true',
      'FLUTTER': '$_flutter/bin/flutter',
      'BUILD_NAME': '1.2.3',
      'BUILD_NUMBER': '45',
    });
    expect(build.passThroughEnvironment, contains('XDG_CONFIG_HOME'));
    expect(build.secretFiles, isEmpty, reason: 'only ship.sh signs');
    final ship = named('ship.sh');
    expect(ship.arguments, [appDirectory], reason: 'no --upload');
    expect(ship.environment, {
      'CI': 'true',
      'FLUTTER': '$_flutter/bin/flutter',
      'BUILD_NUMBER': '45',
      'ASC_EXPORT_OPTIONS': '$appDirectory/ios/ExportOptions.plist',
    });
    expect(ship.secretFiles, _signing);
    expect(checkout.used, [_flutter]);
    expect(
      (await harness.jobs.tools('job_1'))?.iosLinux,
      'Linux, omarchy-apple-dev 2d03f766859e6e4549b949b4afbb8e66d851b18d',
    );
  });

  test('prepares the Flutter install of the version first, once', () async {
    checkout.prepared.clear();

    final outcome = await step.run(input(), context);
    await step.run(input(), context);

    expect(outcome, isA<StepSucceeded<BuildResult>>());
    expect(scripts(), [
      'setup.sh',
      'build.sh',
      'ship.sh',
      'build.sh',
      'ship.sh',
    ]);
    expect(named('setup.sh').environment['FLUTTER'], '$_flutter/bin/flutter');
  });

  test('fails when setup.sh leaves the macOS gen_snapshot', () async {
    checkout.prepared.clear();
    context.onRun = (_) {};

    final outcome = await step.run(input(), context);

    expect(
      (outcome as StepFailed).message,
      'flutter/setup.sh finished, but the iOS gen_snapshot of $_flutter is '
      'still not the Linux build.',
    );
  });

  test('passes the flavor and the entrypoint to build.sh alone', () async {
    final outcome = await step.run(
      input(flavor: 'prod', target: 'lib/main_prod.dart'),
      context,
    );

    expect(outcome, isA<StepSucceeded<BuildResult>>());
    expect(named('build.sh').environment, {
      'CI': 'true',
      'FLUTTER': '$_flutter/bin/flutter',
      'BUILD_NAME': '1.2.3',
      'BUILD_NUMBER': '45',
      'FLAVOR': 'prod',
      'TARGET': 'lib/main_prod.dart',
    });
    expect(
      named('ship.sh').environment.keys,
      isNot(anyOf(contains('FLAVOR'), contains('TARGET'))),
      reason: 'ship.sh reads the configuration build.sh recorded',
    );
  });

  test('maps the defines and obfuscation', () async {
    harness.files
      ..put(
        '$appDirectory/config/prod.json',
        bytes: utf8.encode('{"API_URL": "https://api.mataa.ly", "LEVEL": 3}'),
      )
      ..put('$appDirectory/ios/Runner/Runner.entitlements');

    final outcome = await step.run(
      input(dartDefineFile: 'config/prod.json', obfuscate: true),
      context,
    );

    expect(
      (outcome as StepSucceeded<BuildResult>).result.debugInfoDirectory,
      'build/xpath/debug-info/ios',
    );
    expect(named('build.sh').arguments, [
      appDirectory,
      'API_URL=https://api.mataa.ly',
      'LEVEL=3',
    ]);
    expect(
      named('build.sh').environment,
      containsPair('SPLIT_DEBUG_INFO', 'build/xpath/debug-info/ios'),
    );
    expect(
      named('build.sh').environment,
      containsPair('DART_OBFUSCATION', 'true'),
    );
    expect(
      named('ship.sh').environment.keys,
      isNot(contains('ASC_ENTITLEMENTS_PATH')),
      reason:
          "ship.sh signs with the configuration's CODE_SIGN_ENTITLEMENTS, "
          'as Xcode does, not whatever file is there',
    );
  });

  test('reads a .env define file', () async {
    harness.files.put(
      '$appDirectory/.env',
      bytes: utf8.encode('# comment\nAPI_URL="https://a.ly"\n'),
    );

    await step.run(input(dartDefineFile: '.env'), context);

    expect(named('build.sh').arguments, [appDirectory, 'API_URL=https://a.ly']);
  });

  test('fails on a define file that is missing or not one', () async {
    harness.files.put(
      '$appDirectory/bad.json',
      bytes: utf8.encode('{"nested": {"a": 1}}'),
    );

    final missing = await step.run(input(dartDefineFile: 'no.json'), context);
    final bad = await step.run(input(dartDefineFile: 'bad.json'), context);

    expect(
      (missing as StepFailed).message,
      'There is no define file no.json in the app.',
    );
    expect((bad as StepFailed).message, contains('flat object'));
    expect(context.commands, isEmpty);
  });

  test('needs the signing the planner gives', () async {
    final outcome = await step.run(input(signing: const {}), context);

    expect((outcome as StepFailed).message, contains('cannot sign the build'));
    expect(context.commands, isEmpty);
  });

  test('says which script failed, and stops there', () async {
    for (final (script, code) in [
      ('setup.sh', 3),
      ('build.sh', 4),
      ('ship.sh', 5),
    ]) {
      checkout.prepared.clear();
      if (script != 'setup.sh') checkout.prepared.add(_flutter);
      context = BuildContext(
        onRun: (command) {
          final name = command.executable.split('/').last;
          context.exit = ProcessExit(exitCode: name == script ? code : 0);
        },
      );

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        "omarchy-apple-dev's flutter/$script exited with code $code. The step "
        'log has its output.',
      );
      expect(scripts().last, script);
    }
  });

  test('a cancelled script is a cancelled build', () async {
    context = BuildContext(
      exit: const ProcessExit(exitCode: -1, cancelled: true),
    );

    final outcome = await step.run(input(), context);

    expect((outcome as StepFailed).message, 'The build was cancelled.');
  });

  test('fails when ship.sh leaves no IPA, or an old one', () async {
    context.onRun = (_) {};
    final missing = await step.run(input(), context);
    harness.files.put(
      _ipa,
      modified: harness.files.markedAt.subtract(const Duration(hours: 1)),
    );
    final stale = await step.run(input(), context);

    expect(
      (missing as StepFailed).message,
      'flutter/ship.sh succeeded but left no build/ios-linux/Runner-store.ipa.',
    );
    expect((stale as StepFailed).message, contains('is older than this build'));
  });

  test('fails without a Flutter install for the pin', () async {
    checkout.at = null;
    final outcome = await step.run(
      BuildIosInput(
        settings: BuildSettings(
          worktree: buildWorktree,
          version: AppVersion.parse('1.2.3+45'),
        ),
        exportOptionsPlist: 'ios/ExportOptions.plist',
        linuxSigning: _signing,
      ),
      context,
    );

    expect((outcome as StepFailed).message, contains('does not pin'));
  });

  test('still builds with Xcode on a Mac', () async {
    step = BuildIosStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
      isMacOS: true,
      linux: IosLinuxBuilds(toolchain: harness.toolchain, checkout: checkout),
    );
    context = BuildContext(
      onRun: (_) => harness.files.put('$appDirectory/build/ios/ipa/A.ipa'),
    );

    final outcome = await step.run(input(), context);

    expect(outcome, isA<StepSucceeded<BuildResult>>());
    expect(context.commands.single.executable, '$_flutter/bin/flutter');
  });
}
