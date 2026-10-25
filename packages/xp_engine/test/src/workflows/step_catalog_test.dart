import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('StepKey', () {
    test('takes a value of its shape', () {
      for (final (key, fits, other, problem) in [
        (const StepKey('a'), 'x', 3, '"a" must be a string'),
        (
          const StepKey('a', value: StepValue.flag),
          true,
          'yes',
          '"a" must be true or false',
        ),
        (
          const StepKey('a', value: StepValue.number),
          0.5,
          'lots',
          '"a" must be a number',
        ),
        (
          const StepKey('a', value: StepValue.texts),
          ['x'],
          [1],
          '"a" must be a list of strings',
        ),
        (
          const StepKey('a', value: StepValue.textMap),
          {'k': 'v'},
          {'k': 1},
          '"a" must be a mapping of strings',
        ),
      ]) {
        expect(key.problemOf(fits), isNull, reason: key.value.name);
        expect(key.problemOf(other), problem, reason: key.value.name);
      }
      expect(
        const StepKey('a', value: StepValue.any).problemOf([1, 'x']),
        isNull,
      );
    });

    test('takes a placeholder whatever its shape, known at dispatch', () {
      expect(
        const StepKey('a', value: StepValue.flag).problemOf(r'${{ inputs.f }}'),
        isNull,
      );
    });

    test('takes one of its options, or a list of them', () {
      const artifact = StepKey.choice('artifact', ['apk', 'aab']);
      const checks = StepKey.choice('checks', [
        'source',
      ], value: StepValue.texts);

      expect(artifact.problemOf('aab'), isNull);
      expect(artifact.problemOf('ipa'), '"artifact" takes apk, aab');
      expect(checks.problemOf(['source', r'${{ inputs.c }}']), isNull);
      expect(checks.problemOf(['source', 'nope']), '"checks" takes source');
      expect(artifact.required, isFalse);
    });

    test('gives the schema its type, options, default and description', () {
      expect(
        const StepKey.choice(
          'artifact',
          ['apk', 'aab'],
          description: 'What to build.',
          defaultValue: 'apk',
        ).toWire(),
        const StepKeySchema(
          name: 'artifact',
          type: StepKeyType.string,
          options: ['apk', 'aab'],
          defaultValue: 'apk',
          description: 'What to build.',
        ),
      );
      expect(
        {
          for (final value in StepValue.values)
            value: StepKey('a', value: value).toWire().type,
        },
        {
          StepValue.text: StepKeyType.string,
          StepValue.flag: StepKeyType.boolean,
          StepValue.number: StepKeyType.number,
          StepValue.texts: StepKeyType.list,
          StepValue.textMap: StepKeyType.map,
          StepValue.any: StepKeyType.any,
        },
      );
      expect(
        const StepKey.needed('appId').toWire(),
        const StepKeySchema(
          name: 'appId',
          type: StepKeyType.string,
          required: true,
        ),
      );
    });

    test('can be needed', () {
      const key = StepKey.needed('exportOptionsPlist');

      expect(key.required, isTrue);
      expect(key.value, StepValue.text);
      expect(key.options, isNull);
    });
  });

  group('MapStepCatalog', () {
    const catalog = MapStepCatalog(
      {
        'b': {'x', 'y'},
        'a': {},
      },
      typed: {
        'b': [StepKey.needed('x')],
      },
    );

    test('lists its step types and their keys', () {
      expect(catalog.kinds, ['a', 'b']);
      expect(catalog.withKeys('b'), {'x', 'y'});
      expect(catalog.withKeys('c'), isNull);
    });

    test('types the keys it was told about, and takes anything else', () {
      final keys = catalog.keysOf('b')!;

      expect(keys['x']!.required, isTrue);
      expect(keys['y']!.value, StepValue.any);
      expect(catalog.keysOf('a'), isEmpty);
      expect(catalog.keysOf('c'), isNull);
    });

    test('describes a step type by its kind and keys', () {
      expect(
        catalog.describe('b'),
        const StepType(
          kind: 'b',
          withKeys: ['x', 'y'],
          title: 'b',
          keys: [
            StepKeySchema(name: 'x', type: StepKeyType.string, required: true),
            StepKeySchema(name: 'y'),
          ],
        ),
      );
      expect(catalog.describe('c'), isNull);
    });
  });
}
