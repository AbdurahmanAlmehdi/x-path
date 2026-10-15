import 'package:test/test.dart';
import 'package:xp_repositories/xp_repositories.dart';

void main() {
  group('WorkflowOutline', () {
    test('reads stages, jobs, matrices and steps', () {
      final outline = WorkflowOutline.parse(r'''
schema: 1
name: Production release
lock: project
inputs:
  notes:
    default: ""
  appleAppIds:
    description: By flavor.
  plain: x
stages:
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: [prod]
        if: flavor.prod
        capabilities: [flutter, 3]
        steps:
          - kind: build.ios
            if: platform == 'ios'
          - kind: git.push
            gate: push
          - with: {a: 1}
          - plain
      broken: x
  - not a stage
  - name: empty
''');
      expect(outline.name, 'Production release');
      expect(outline.locksProject, isTrue);
      expect(outline.inputDefaults, {
        'notes': '',
        'appleAppIds': null,
        'plain': null,
      });
      expect(outline.stages, const [
        StageOutline(
          name: 'build',
          jobs: [
            JobOutline(
              id: 'build',
              name: r'Build ${{ flavor.name }} for ${{ platform }}',
              matrix: {
                'platform': r'${{ platforms }}',
                'flavor': ['prod'],
              },
              condition: 'flavor.prod',
              capabilities: ['flutter'],
              steps: [
                StepOutline(kind: 'build.ios', condition: "platform == 'ios'"),
                StepOutline(kind: 'git.push', gate: 'push'),
              ],
            ),
          ],
        ),
        StageOutline(name: 'empty'),
      ]);
    });

    test('reads what it can of a sparse document', () {
      expect(
        WorkflowOutline.parse('name: 3\nlock: none\n'),
        const WorkflowOutline(),
      );
      expect(
        WorkflowOutline.parse('stages:\n  - jobs: {}\n'),
        const WorkflowOutline(stages: [StageOutline(name: '')]),
      );
    });

    test('refuses what is not a YAML mapping', () {
      expect(
        () => WorkflowOutline.parse('- a\n- b\n'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => WorkflowOutline.parse('a: [b\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
