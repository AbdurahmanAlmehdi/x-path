@Tags(['process'])
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/process_helpers.dart';

/// A started process whose lines are collected.
class _Run {
  new(this.process, this.lines, this.exit);

  final SupervisedProcess process;
  final List<OutputLine> lines;
  final Future<ProcessExit> exit;

  List<String> get texts => [for (final line in lines) line.text];
}

void main() {
  late ManualClock clock;
  late Directory directory;
  final environment = {'PATH': Platform.environment['PATH']!};

  IoProcessSupervisor supervisor({
    OutputMasker masker = const NoMasking(),
    Duration grace = const Duration(milliseconds: 400),
    Duration drainTimeout = const Duration(seconds: 2),
    String? path,
    ProcessGroupControl control = const IoProcessGroupControl(),
  }) => IoProcessSupervisor(
    masker: masker,
    clock: clock,
    grace: grace,
    pollInterval: const Duration(milliseconds: 20),
    drainTimeout: drainTimeout,
    path: path,
    control: control,
  );

  Future<_Run> launch(
    IoProcessSupervisor supervisor,
    String executable,
    List<String> arguments, {
    Map<String, String>? env,
    String? workingDirectory,
    int capacity = 256,
  }) async {
    final process = await supervisor.start(
      ProcessSpec(
        executable,
        arguments,
        environment: env ?? environment,
        workingDirectory: workingDirectory,
      ),
    );
    final lines = <OutputLine>[];
    final reading = process.output
        .subscribe(capacity: capacity)
        .listen(lines.add);
    addTearDown(reading.cancel);
    return _Run(process, lines, process.run());
  }

  Future<_Run> sh(
    String script, {
    IoProcessSupervisor? with_,
    Map<String, String>? env,
  }) => launch(with_ ?? supervisor(), 'sh', ['-c', script], env: env);

  /// Waits for the line `gc=<pid>` and returns the pid.
  Future<int> grandchild(_Run run) async {
    for (var i = 0; i < 500; i++) {
      final line = run.lines.where((l) => l.text.startsWith('gc=')).firstOrNull;
      if (line != null) {
        return int.parse(line.text.substring(3));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('No grandchild was reported.');
  }

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    directory = Directory.systemTemp.createTempSync('xp_supervisor_');
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  group('output', () {
    test('streams lines in order with sequence numbers and times', () async {
      final run = await sh('echo one; echo two; echo three');

      final exit = await run.exit;

      expect(exit, const ProcessExit(exitCode: 0));
      expect(run.texts, ['one', 'two', 'three']);
      expect(run.lines.map((l) => l.seq), [1, 2, 3]);
      expect(run.lines.map((l) => l.timestamp), everyElement(clock.now()));
      expect(run.lines.map((l) => l.stream), everyElement(LogStream.stdout));
    });

    test('keeps standard output and error apart, one numbering', () async {
      final run = await sh('echo out; sleep 0.2; echo err >&2');

      await run.exit;

      expect(run.lines.map((l) => (l.seq, l.stream, l.text)), [
        (1, LogStream.stdout, 'out'),
        (2, LogStream.stderr, 'err'),
      ]);
    });

    test('ends lines at CRLF and CR, and flushes a last line', () async {
      final run = await sh(r"printf 'a\r\nb\rc\nlast'");

      await run.exit;

      expect(run.texts, ['a', 'b', 'c', 'last']);
    });

    test('decodes UTF-8 and replaces invalid bytes', () async {
      final run = await sh(r"printf 'caf\303\251 \377!\n'");

      await run.exit;

      expect(run.texts, ['café �!']);
    });

    test('cuts a very long line', () async {
      final run = await sh(r"head -c 40000 /dev/zero | tr '\0' x; echo");

      await run.exit;

      expect(run.texts.map((t) => t.length), [16384, 16384, 7232]);
    });

    test('hands every line to a slow reader, in order', () async {
      final run = await sh(
        r'i=0; while [ $i -lt 300 ]; do echo line$i; i=$((i+1)); done',
      );
      final slow = <String>[];
      final reading = run.process.output.subscribe(capacity: 2).listen((line) {
        slow.add(line.text);
      });
      addTearDown(reading.cancel);

      await run.exit;

      expect(run.texts, [for (var i = 0; i < 300; i++) 'line$i']);
      expect(slow, run.texts);
    });

    test('passes lines through the masker, one stream per pipe', () async {
      final masker = LaggingMasker(['s3cret-value']);
      final run = await sh(
        'echo "token s3cret-value ok"; echo "err s3cret-value" >&2',
        with_: supervisor(masker: masker),
      );

      await run.exit;

      expect(run.texts, unorderedEquals(['token *** ok', 'err ***']));
      expect(masker.streams, 2);
    });

    test('stops reading after a process left a daemon on the pipes', () async {
      final run = await sh(
        r'sleep 30 & echo "gc=$!"; echo done',
        with_: supervisor(drainTimeout: const Duration(milliseconds: 300)),
      );
      final daemon = await grandchild(run);
      addTearDown(() {
        if (processAlive(daemon)) {
          Process.killPid(daemon, ProcessSignal.sigkill);
        }
      });

      final exit = await run.exit.timeout(const Duration(seconds: 5));

      expect(exit.exitCode, 0);
      expect(run.texts, contains('done'));
      expect(processAlive(daemon), isTrue, reason: 'only a cancel stops it');
    });
  });

  group('environment', () {
    test('is exactly the one in the spec', () async {
      final run = await sh(
        r'echo "ONLY=$ONLY HOME=${HOME-unset} TOKEN=${GITHUB_TOKEN-unset}"',
        env: {...environment, 'ONLY': 'yes'},
      );

      await run.exit;

      expect(run.texts, ['ONLY=yes HOME=unset TOKEN=unset']);
    });

    test('runs in the working directory', () async {
      final run = await launch(supervisor(), 'pwd', [
        '-P',
      ], workingDirectory: directory.path);

      await run.exit;

      expect(run.texts, [directory.resolveSymbolicLinksSync()]);
    });

    test('passes arguments untouched, through no shell', () async {
      final run = await launch(supervisor(), 'sh', [
        '-c',
        r'printf "[%s]\n" "$@"',
        'sh',
        '-x',
        'a b',
        r'$HOME',
        ';echo pwned',
        '',
      ]);

      await run.exit;

      expect(run.texts, ['[-x]', '[a b]', r'[$HOME]', '[;echo pwned]', '[]']);
    });

    test('runs a program with shell characters in its name as it is', () async {
      final script = File(p.join(directory.path, 'run me;echo pwned'))
        ..writeAsStringSync('#!/bin/sh\necho ran\n');
      Process.runSync('chmod', ['+x', script.path]);

      final run = await launch(supervisor(), script.path, const []);

      await run.exit;

      expect(run.texts, ['ran']);
    });

    test('closes standard input', () async {
      final run = await launch(supervisor(), 'cat', const []);

      expect(
        await run.exit.timeout(const Duration(seconds: 5)),
        isA<ProcessExit>(),
      );
      expect(run.texts, isEmpty);
    });
  });

  group('exit', () {
    test('reports the exit code', () async {
      final run = await sh('exit 3');

      expect(await run.exit, const ProcessExit(exitCode: 3));
    });

    test('is its own process group, led by the process', () async {
      final run = await sh(r'echo "gc=$$"; sleep 0.3');

      final pid = await grandchild(run);

      expect(pid, run.process.pid);
      expect(processGroup(run.process.pid), run.process.pid);
      await run.exit;
    });
  });

  group('cancel', () {
    test('stops a grandchild too', () async {
      final run = await sh(r'sleep 300 & echo gc=$!; wait');
      final child = await grandchild(run);
      expect(processAlive(child), isTrue);
      expect(processGroup(child), run.process.pid);

      await run.process.cancel();
      final exit = await run.exit;

      expect(exit, const ProcessExit(exitCode: -15, cancelled: true));
      expect(processAlive(child), isFalse, reason: 'grandchild must die');
    });

    test(
      'kills a group that ignores SIGTERM once the grace has passed',
      () async {
        final run = await sh(
          r'trap "" TERM; sleep 300 & echo gc=$!; wait',
          with_: supervisor(grace: const Duration(milliseconds: 300)),
        );
        final child = await grandchild(run);
        final stopwatch = Stopwatch()..start();

        await run.process.cancel();
        final exit = await run.exit;

        expect(exit, const ProcessExit(exitCode: -9, cancelled: true));
        expect(processAlive(child), isFalse);
        expect(
          stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 300)),
          reason: 'it waited the grace period before SIGKILL',
        );
      },
    );

    test('is safe to call twice, and after the process ended', () async {
      final run = await sh('sleep 300');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await Future.wait([run.process.cancel(), run.process.cancel()]);
      await run.exit;
      await run.process.cancel();
    });

    test('does not mark a process cancelled that ended by itself', () async {
      final run = await sh('echo done');

      final exit = await run.exit;

      expect(exit.cancelled, isFalse);
    });

    test('before the output is read still stops the process', () async {
      final process = await supervisor().start(
        ProcessSpec('sleep', const ['300'], environment: environment),
      );

      await process.cancel();
      final exit = await process.run();

      expect(exit.cancelled, isTrue);
      expect(processAlive(process.pid), isFalse);
    });

    test('kills the leader directly when its group is gone', () async {
      final control = _AlwaysDeadControl();
      final process = await supervisor(control: control)
          .start(ProcessSpec('sleep', const ['300'], environment: environment));

      await process.cancel();
      final exit = await process.run();

      expect(exit, const ProcessExit(exitCode: -9, cancelled: true));
    });
  });

  group('start', () {
    test(
      'throws a ProcessStartException for a program that is not there',
      () async {
        await expectLater(
          supervisor().start(
            ProcessSpec(
              'no-such-program-xp',
              const [],
              environment: environment,
            ),
          ),
          throwsA(
            isA<ProcessStartException>().having(
              (e) => e.executable,
              'executable',
              'no-such-program-xp',
            ),
          ),
        );
      },
    );

    test('does not find a program outside the PATH of the spec', () async {
      await expectLater(
        supervisor().start(
          const ProcessSpec('sh', ['-c', 'true'], environment: {}),
        ),
        throwsA(isA<ProcessStartException>()),
      );
    });

    test('throws a ProcessStartException when the folder is missing', () async {
      await expectLater(
        supervisor().start(
          ProcessSpec(
            'true',
            const [],
            environment: environment,
            workingDirectory: p.join(directory.path, 'nope'),
          ),
        ),
        throwsA(isA<ProcessStartException>()),
      );
    });

    test('reports a missing perl as a toolchain error', () async {
      final empty = Directory(p.join(directory.path, 'empty'))..createSync();
      final noPerl = supervisor(path: empty.path);

      expect(
        noPerl.requirePerl,
        throwsA(
          isA<ToolchainException>()
              .having((e) => e.tool, 'tool', 'perl')
              .having((e) => e.message, 'message', contains('perl-base')),
        ),
      );
      await expectLater(
        noPerl.start(ProcessSpec('true', const [], environment: environment)),
        throwsA(isA<ToolchainException>()),
      );
    });

    test('finds perl on the PATH it is given', () {
      final perl = supervisor().requirePerl();

      expect(p.basename(perl), 'perl');
      expect(File(perl).existsSync(), isTrue);
    });

    test('uses the PATH of the engine by default', () {
      final defaulted = IoProcessSupervisor(
        masker: const NoMasking(),
        clock: clock,
      );

      expect(p.basename(defaulted.requirePerl()), 'perl');
    });
  });
}

/// A control that never finds a group, as when the leader never became one.
class _AlwaysDeadControl implements ProcessGroupControl {
  @override
  bool isAlive(int pgid) => false;

  @override
  void terminate(int pgid) {}

  @override
  void kill(int pgid) {}
}
