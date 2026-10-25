import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late Directory work;
  late String installs;
  late ManualClock clock;
  late FakeProcessRunner runner;
  late ProcessOutput Function() git;

  DirectoryIosLinuxToolchain toolchain() => DirectoryIosLinuxToolchain(
    directory: '/opt/omarchy-apple-dev',
    installs: installs,
    runner: runner,
    clock: clock,
  );

  /// An install of [version] whose `gen_snapshot` starts with [head].
  String install(String version, {List<int>? head}) {
    final root = p.join(installs, version);
    Directory(root).createSync(recursive: true);
    if (head != null) {
      File(p.join(root, DirectoryIosLinuxToolchain.genSnapshot))
        ..createSync(recursive: true)
        ..writeAsBytesSync([...head, 0, 0]);
    }
    return root;
  }

  setUp(() {
    work = Directory.systemTemp.createTempSync('xp_ios_linux_');
    addTearDown(() => work.deleteSync(recursive: true));
    installs = p.join(work.path, 'toolchains', 'flutter-ios-linux');
    clock = ManualClock(DateTime.utc(2026, 10, 25));
    git = () => const ProcessOutput(exitCode: 0, stdout: 'abc123\n');
    runner = FakeProcessRunner((call) {
      if (call.executable == 'git') return git();
      throw ProcessStartException(call.executable, 'not found');
    });
  });

  test('reads the commit of the checkout', () async {
    expect(await toolchain().commit(), 'abc123');
    expect(runner.calls.single.arguments, [
      '-C',
      '/opt/omarchy-apple-dev',
      'rev-parse',
      'HEAD',
    ]);
    git = () => const ProcessOutput(exitCode: 128, stderr: 'not a repo');
    expect(await toolchain().commit(), isNull);
  });

  test('has no commit without git', () async {
    runner = FakeProcessRunner(
      (call) => throw ProcessStartException(call.executable, 'not found'),
    );

    expect(await toolchain().commit(), isNull);
  });

  test('is prepared once gen_snapshot is the Linux (ELF) build', () async {
    final linux = install('3.47.6', head: [0x7f, 0x45, 0x4c, 0x46]);
    final mac = install('3.47.5', head: [0xcf, 0xfa, 0xed, 0xfe]);
    final none = install('3.47.4');

    expect(await toolchain().isPrepared(linux), isTrue);
    expect(await toolchain().isPrepared(mac), isFalse);
    expect(await toolchain().isPrepared(none), isFalse);
  });

  test('frees the installs no job used for 30 days', () async {
    final current = install('3.47.6');
    final recent = install('3.47.5');
    final old = install('3.44.0');
    install('.install-3.48.0-x');
    await toolchain().markUsed(recent);
    await toolchain().markUsed(old);
    clock.advance(const Duration(days: 20));
    await toolchain().markUsed(recent);
    clock.advance(const Duration(days: 11));

    final freed = await toolchain().markUsed(current);

    expect(freed, ['3.44.0']);
    expect(Directory(old).existsSync(), isFalse);
    expect(Directory(recent).existsSync(), isTrue);
    expect(
      File(p.join(current, '.xpath-last-used')).readAsStringSync(),
      clock.now().toIso8601String(),
    );
    expect(
      Directory(p.join(installs, '.install-3.48.0-x')).existsSync(),
      isTrue,
    );
  });

  test('judges an install without a mark by its folder', () async {
    final current = install('3.47.6');
    final unmarked = install('3.40.0');

    expect(await toolchain().markUsed(current), isEmpty);
    clock.advance(const Duration(days: 365 * 10));
    expect(await toolchain().markUsed(current), ['3.40.0']);
    expect(Directory(unmarked).existsSync(), isFalse);
  });

  test('frees nothing when there are no installs yet', () async {
    final elsewhere = p.join(work.path, 'other');
    Directory(elsewhere).createSync();

    expect(await toolchain().markUsed(elsewhere), isEmpty);
  });
}
