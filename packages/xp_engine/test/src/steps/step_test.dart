import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('StepPlan', () {
    test('holds the stored form of a step', () {
      const plan = StepPlan(kind: 'x', input: {'a': 1}, sideEffect: true);

      expect(plan.kind, 'x');
      expect(plan.input, {'a': 1});
      expect(plan.sideEffect, isTrue);
    });

    test('is made from a step and its input', () {
      final plan = StepPlan.of(
        const CommandStep(),
        const CommandInput(ProcessCommand('ls'), sideEffect: true),
      );

      expect(plan.kind, 'command');
      expect(plan.input['executable'], 'ls');
      expect(plan.sideEffect, isTrue);
    });
  });

  group('StepRegistry', () {
    test('finds a step by kind', () {
      const command = CommandStep();
      final registry = StepRegistry([command]);

      expect(registry['command'], same(command));
      expect(registry['nope'], isNull);
      expect(registry.kinds, ['command']);
    });

    test('rejects two steps of the same kind', () {
      expect(
        () => StepRegistry([const CommandStep(), const CommandStep()]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('outcomes', () {
    test('carry their data', () {
      expect(const StepSucceeded(3).result, 3);
      expect(const StepFailed('no').message, 'no');
      expect(const StepSkipped('later').reason, 'later');
    });
  });
}
