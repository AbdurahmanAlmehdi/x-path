import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

const _catalog = MapStepCatalog({
  'guard': {'checks'},
});

JobDefinition _job(String matrix) {
  final result = const WorkflowParser(_catalog).parse('''
schema: 1
stages:
  - name: a
    jobs:
      j:
        matrix:
$matrix
        steps:
          - kind: guard
''');
  expect(result.issues, isEmpty);
  return result.definition!.jobs.single;
}

void main() {
  const scope = {
    'platforms': ['android', 'ios'],
    'flavors': ['dev', 'prod'],
  };

  test('is one empty cell without a matrix', () {
    final job = const WorkflowParser(_catalog)
        .parse('''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: guard
''')
        .definition!
        .jobs
        .single;

    expect(expandMatrix(job, scope), [<String, String>{}]);
  });

  test('is every combination, in the order of the axes and values', () {
    final job = _job(r'''
          platform: ${{ platforms }}
          flavor: ${{ flavors }}''');

    expect(expandMatrix(job, scope), [
      {'platform': 'android', 'flavor': 'dev'},
      {'platform': 'android', 'flavor': 'prod'},
      {'platform': 'ios', 'flavor': 'dev'},
      {'platform': 'ios', 'flavor': 'prod'},
    ]);
  });

  test('takes values written out', () {
    final job = _job('          flavor: [qa]');

    expect(expandMatrix(job, scope), [
      {'flavor': 'qa'},
    ]);
  });

  test('is empty when an axis has no values', () {
    final job = _job(r'          platform: ${{ platforms }}');

    expect(expandMatrix(job, {'platforms': <String>[]}), isEmpty);
  });

  test('refuses an axis that is not a list of strings', () {
    final job = _job(r'          platform: ${{ platforms }}');

    for (final bad in <Object?>[
      'ios',
      null,
      <Object?>[1],
    ]) {
      expect(
        () => expandMatrix(job, {'platforms': bad}),
        throwsA(
          isA<DispatchException>().having(
            (e) => e.message,
            'message',
            startsWith('Line 7: the matrix axis "platform" must give a list'),
          ),
        ),
      );
    }
  });
}
