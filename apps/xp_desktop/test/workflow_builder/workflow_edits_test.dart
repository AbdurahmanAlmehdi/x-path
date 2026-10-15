import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';
import 'package:xp_repositories/xp_repositories.dart';

const _document = WorkflowDocument(
  stages: [
    WorkflowStage(
      name: 'check',
      jobs: [WorkflowJob(id: 'check')],
    ),
    WorkflowStage(
      name: 'build',
      jobs: [
        WorkflowJob(id: 'build'),
        WorkflowJob(id: 'build-2'),
      ],
    ),
  ],
);

void main() {
  group('WorkflowSelection.within', () {
    test('keeps what the document has and clamps the rest', () {
      expect(
        const WorkflowSelection(stage: 1, job: 1).within(_document),
        const WorkflowSelection(stage: 1, job: 1),
      );
      expect(
        const WorkflowSelection(stage: 5, job: 5).within(_document),
        const WorkflowSelection(stage: 1, job: 1),
      );
      expect(
        const WorkflowSelection(stage: 0).within(_document),
        const WorkflowSelection(stage: 0),
      );
      expect(
        WorkflowSelection.workflow.within(_document),
        WorkflowSelection.workflow,
      );
      expect(
        const WorkflowSelection(
          stage: 0,
          job: 0,
        ).within(const WorkflowDocument()),
        WorkflowSelection.workflow,
      );
      expect(
        const WorkflowSelection(stage: 0, job: 0).within(
          const WorkflowDocument(stages: [WorkflowStage(name: 'empty')]),
        ),
        const WorkflowSelection(stage: 0),
      );
    });
  });

  group('WorkflowEdits', () {
    test('add, edit, move and remove stages', () {
      final added = _document.addStage('ship');
      expect(
        added.stages.last,
        const WorkflowStage(
          name: 'ship',
          jobs: [WorkflowJob(id: 'ship')],
        ),
      );
      expect(
        added.editStage(2, (s) => s.copyWith(name: 'deploy')).stages[2].name,
        'deploy',
      );
      expect(_document.moveStage(1, -1).stages.map((s) => s.name), [
        'build',
        'check',
      ]);
      expect(_document.moveStage(0, -1), _document);
      expect(_document.moveStage(1, 1), _document);
      expect(_document.removeStage(0).stages.single.name, 'build');
      expect(_document.stages, hasLength(2));
    });

    test('add, edit, move and remove jobs with ids no other job has', () {
      final added = _document.addJob(1);
      expect(added.stages[1].jobs.last.id, 'build-3');
      expect(
        _document.editJob(0, 0, (j) => j.copyWith(id: 'lint')).stages[0].jobs,
        const [WorkflowJob(id: 'lint')],
      );
      expect(_document.moveJob(1, 1, -1).stages[1].jobs.map((j) => j.id), [
        'build-2',
        'build',
      ]);
      expect(_document.removeJob(1, 0).stages[1].jobs.map((j) => j.id), [
        'build-2',
      ]);
      expect(_document.uniqueJobId('upload'), 'upload');
      expect(_document.uniqueJobId(''), 'job');
    });

    test('add, edit, move and remove steps', () {
      const job = WorkflowJob(
        id: 'j',
        steps: [
          WorkflowStep(kind: 'a'),
          WorkflowStep(kind: 'b'),
        ],
      );
      expect(job.addStep('c').steps.last, const WorkflowStep(kind: 'c'));
      expect(
        job.editStep(0, (s) => s.copyWith(gate: () => 'push')).steps.first,
        const WorkflowStep(kind: 'a', gate: 'push'),
      );
      expect(job.moveStep(0, 1).steps.map((s) => s.kind), ['b', 'a']);
      expect(job.removeStep(1).steps.map((s) => s.kind), ['a']);
    });

    test('set, replace and clear an axis of the matrix', () {
      const job = WorkflowJob(id: 'j');
      const platforms = WorkflowMatrixAxis.placeholder(
        'platform',
        r'${{ platforms }}',
      );
      const ios = WorkflowMatrixAxis.list('platform', ['ios']);
      const flavors = WorkflowMatrixAxis.list('flavor', ['prod']);

      final set = job
          .withAxis('platform', platforms)
          .withAxis('flavor', flavors);
      expect(set.matrix, const [platforms, flavors]);
      expect(set.axis('platform'), platforms);
      expect(set.withAxis('platform', ios).matrix, const [ios, flavors]);
      expect(set.withAxis('platform', null).matrix, const [flavors]);
      expect(job.withAxis('flavor', null), job);
      expect(job.axis('flavor'), isNull);
    });
  });
}
