import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('an in-memory workspace reads, lists and writes', () async {
    final workspace = InMemoryWorkspace({'a/b.txt': 'one', 'c.txt': 'two'});

    expect(await workspace.exists('a'), isTrue);
    expect(await workspace.read('c.txt'), 'two');
    expect(await workspace.list(''), const [
      ScanEntry('a', isDirectory: true),
      ScanEntry('c.txt', isDirectory: false),
    ]);

    await workspace.write('c.txt', 'three');

    expect(await workspace.read('c.txt'), 'three');
    expect(workspace.writes, ['c.txt']);
  });

  test('an in-memory workspace writes only to files that exist', () {
    final workspace = InMemoryWorkspace({'a.txt': 'one'});

    expect(() => workspace.write('b.txt', 'x'), throwsStateError);
    expect(workspace.writes, isEmpty);
  });
}
