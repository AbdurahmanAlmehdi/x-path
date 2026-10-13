import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';

LogLineFrame _line(int seq, String text, {int step = 0}) => LogLineFrame(
  seq: seq,
  step: step,
  at: DateTime.utc(2026, 10, 13, 9, 0, seq),
  stream: LogStream.stdout,
  text: text,
);

void main() {
  late Directory root;
  late FileJobLogStore store;

  Future<void> write(
    String jobId,
    int ordinal,
    String kind,
    List<LogLineFrame> lines,
  ) async {
    final writer = await store.open(jobId: jobId, ordinal: ordinal, kind: kind);
    for (final line in lines) {
      await writer.write(line);
    }
    await writer.close();
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_logs_');
    store = FileJobLogStore(p.join(root.path, 'logs'));
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test(
    'writes a JSON line per log line under <job>/<ordinal>-<kind>.log',
    () async {
      final writer = await store.open(
        jobId: 'job_1',
        ordinal: 2,
        kind: 'command',
      );
      await writer.write(_line(1, 'hello'));
      await writer.close();

      expect(writer.path, p.join(root.path, 'logs', 'job_1', '2-command.log'));
      final text = File(writer.path).readAsStringSync();
      expect(text.endsWith('\n'), isTrue);
      expect(jsonDecode(text.trim()), _line(1, 'hello').toJson());
    },
  );

  test('keeps a kind with odd characters a plain file name', () async {
    final writer = await store.open(
      jobId: 'job_1',
      ordinal: 0,
      kind: '../build/ios x',
    );
    await writer.close();

    expect(p.basename(writer.path), '0-.._build_ios_x.log');
    expect(p.dirname(writer.path), p.join(root.path, 'logs', 'job_1'));
  });

  test('can be read while it is being written', () async {
    final writer = await store.open(jobId: 'job_1', ordinal: 0, kind: 'x');
    await writer.write(_line(1, 'first'));

    expect((await store.read('job_1').toList()).map((l) => l.text), ['first']);
    expect(await store.head('job_1'), 1);

    await writer.write(_line(2, 'second'));
    await writer.close();

    expect(await store.head('job_1'), 2);
  });

  test(
    'reads the lines of every step, in step order, after a cursor',
    () async {
      await write('job_1', 10, 'c', [_line(5, 'e', step: 10)]);
      await write('job_1', 2, 'b', [
        _line(3, 'c', step: 2),
        _line(4, 'd', step: 2),
      ]);
      await write('job_1', 0, 'a', [_line(1, 'a'), _line(2, 'b')]);

      expect((await store.read('job_1').toList()).map((l) => l.text), [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect((await store.read('job_1', after: 3).toList()).map((l) => l.seq), [
        4,
        5,
      ]);
      expect(await store.read('job_1', after: 5).toList(), isEmpty);
    },
  );

  test('appends when a step runs again', () async {
    await write('job_1', 0, 'x', [_line(1, 'first try')]);
    await write('job_1', 0, 'x', [_line(2, 'second try')]);

    expect((await store.read('job_1').toList()).map((l) => l.text), [
      'first try',
      'second try',
    ]);
  });

  test('knows the newest line of a job, 0 for none', () async {
    expect(await store.head('job_x'), 0);

    await write('job_1', 0, 'a', [_line(1, 'a'), _line(2, 'b')]);
    await write('job_1', 1, 'b', [_line(3, 'c')]);
    await write('job_1', 2, 'c', const []);

    expect(await store.head('job_1'), 3);
    expect(await store.read('job_x').toList(), isEmpty);
  });

  test('skips a torn last line and lines that are not log lines', () async {
    await write('job_1', 0, 'x', [_line(1, 'ok')]);
    const gap = LogGapFrame(fromSeq: 1, toSeq: 2, count: 2);
    File(p.join(root.path, 'logs', 'job_1', '0-x.log'))
      ..writeAsStringSync('not json\n', mode: FileMode.append)
      ..writeAsStringSync('[1, 2]\n', mode: FileMode.append)
      ..writeAsStringSync(
        '${jsonEncode(gap.toJson())}\n',
        mode: FileMode.append,
      )
      ..writeAsStringSync('{"type":"line","seq":2', mode: FileMode.append);

    expect((await store.read('job_1').toList()).map((l) => l.text), ['ok']);
    expect(await store.head('job_1'), 1);
  });

  test('ignores files that are not step logs', () async {
    await write('job_1', 0, 'x', [_line(1, 'ok')]);
    File(p.join(root.path, 'logs', 'job_1', 'notes.txt'))
        .writeAsStringSync('x');
    Directory(p.join(root.path, 'logs', 'job_1', '9-dir.log')).createSync();

    expect((await store.read('job_1').toList()).map((l) => l.text), ['ok']);
  });
}
