import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/update/update_journal.dart';

void main() {
  late Directory directory;
  late UpdateJournal journal;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_journal_');
    addTearDown(() => directory.deleteSync(recursive: true));
    journal = UpdateJournal(p.join(directory.path, 'sub', 'update.json'));
  });

  test('knows of no update to begin with', () {
    expect(journal.pending, isNull);
    expect(journal.blocked, isNull);
    expect(journal.noteStart('1.0.0'), isA<ProceedStart>());
    expect(journal.confirm('1.0.0'), isNull);
  });

  test('keeps the update that is switched to, and writes nothing else', () {
    journal.begin(from: '1.0.0', to: '1.1.0');

    expect(journal.pending!.from, '1.0.0');
    expect(journal.pending!.to, '1.1.0');
    expect(journal.pending!.starts, 0);
    expect(File('${journal.path}.partial').existsSync(), isFalse);
  });

  test('counts the starts of the new version up to the limit', () {
    journal.begin(from: '1.0.0', to: '1.1.0');

    for (var start = 1; start <= maxUnconfirmedStarts; start++) {
      expect(journal.noteStart('1.1.0'), isA<ProceedStart>());
      expect(journal.pending!.starts, start);
    }
    final decision = journal.noteStart('1.1.0');

    expect(decision, isA<RollBack>());
    expect((decision as RollBack).version, '1.0.0');
    expect(decision.failed, '1.1.0');
  });

  test('drops an update of another version than the one that runs', () {
    journal.begin(from: '1.0.0', to: '1.1.0');

    expect(journal.noteStart('1.0.0'), isA<ProceedStart>());

    expect(journal.pending, isNull);
    expect(File(journal.path).existsSync(), isFalse);
  });

  test('confirms an update once, and says what to keep', () {
    journal.begin(from: '1.0.0', to: '1.1.0');

    expect(journal.confirm('1.0.0'), isNull);
    expect(journal.pending, isNotNull);
    expect(journal.confirm('1.1.0'), '1.0.0');
    expect(journal.pending, isNull);
    expect(journal.confirm('1.1.0'), isNull);
  });

  test('remembers the version that failed, across everything else', () {
    journal
      ..begin(from: '1.0.0', to: '1.1.0')
      ..rolledBack('1.1.0');

    expect(journal.pending, isNull);
    expect(journal.blocked, '1.1.0');

    journal.begin(from: '1.0.0', to: '1.2.0');
    expect(journal.blocked, '1.1.0');
    journal.noteStart('1.2.0');
    expect(journal.blocked, '1.1.0');
    expect(journal.confirm('1.2.0'), '1.0.0');
    expect(journal.blocked, '1.1.0');
    journal.abandon();
    expect(journal.blocked, '1.1.0');
  });

  test('abandons the update that could not be switched to', () {
    journal
      ..begin(from: '1.0.0', to: '1.1.0')
      ..abandon();

    expect(journal.pending, isNull);
    expect(File(journal.path).existsSync(), isFalse);
  });

  test('takes a file it cannot read for no record', () {
    File(journal.path)
      ..createSync(recursive: true)
      ..writeAsStringSync('{ not json');

    expect(journal.pending, isNull);
    expect(journal.blocked, isNull);
    expect(journal.noteStart('1.0.0'), isA<ProceedStart>());

    File(journal.path).writeAsStringSync(
      jsonEncode({
        'pending': {'from': 1},
      }),
    );
    expect(journal.pending, isNull);
  });

  test('round-trips a pending update', () {
    const pending = PendingUpdate(from: 'a', to: 'b', starts: 2);

    final again = PendingUpdate.fromJson(pending.toJson());

    expect((again.from, again.to, again.starts), ('a', 'b', 2));
  });
}
