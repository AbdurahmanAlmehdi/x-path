import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late Directory directory;
  late FakeProcessGroupControl control;
  late ProcessGroupKiller killer;
  late PgidJournal journal;

  File file() => File(p.join(directory.path, 'pgids.json'));

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_pgids_');
    addTearDown(() => directory.deleteSync(recursive: true));
    control = FakeProcessGroupControl(alive: [4001, 4002]);
    killer = ProcessGroupKiller(control: control, delay: (_) async {});
    journal = PgidJournal(directory.path);
  });

  test('keeps the groups of running steps on disk', () async {
    await journal.track('job_1', 1, 4001);
    await journal.track('job_2', 0, 4002);

    expect(jsonDecode(file().readAsStringSync()), {
      'job_1/1': 4001,
      'job_2/0': 4002,
    });
  });

  test(
    'forgets a group when the step ends, and the file with the last',
    () async {
      await journal.track('job_1', 1, 4001);
      await journal.track('job_2', 0, 4002);

      await journal.track('job_1', 1, null);
      expect(jsonDecode(file().readAsStringSync()), {'job_2/0': 4002});
      await journal.track('job_2', 0, null);

      expect(file().existsSync(), isFalse);
    },
  );

  test('has nothing to do for a step that had no group', () async {
    await journal.track('job_1', 1, null);

    expect(file().existsSync(), isFalse);
  });

  test('stops the groups an earlier run left, once', () async {
    await journal.track('job_1', 1, 4001);
    await journal.track('job_2', 0, 4002);
    final restarted = PgidJournal(directory.path);

    final signalled = await restarted.reap(killer);

    expect(signalled, 2);
    expect(control.alive, isEmpty);
    expect(file().existsSync(), isFalse);
    expect(await restarted.reap(killer), 0);
  });

  test('does nothing when no run left a group', () async {
    expect(await journal.reap(killer), 0);
  });

  test('ignores a file the crash left half written', () async {
    file().writeAsStringSync('{"job_1/1": 40');

    expect(await journal.reap(killer), 0);
    expect(file().existsSync(), isFalse);
    expect(control.alive, {4001, 4002});
  });

  test('ignores entries that are not groups', () async {
    file().writeAsStringSync(jsonEncode({'job_1/1': 'x', 'job_2/0': 4002}));

    expect(await journal.reap(killer), 1);
    expect(control.alive, {4001});
  });

  test('ignores a file that is not an object', () async {
    file().writeAsStringSync('[1, 2]');

    expect(await journal.reap(killer), 0);
  });
}
