import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/all_steps.dart';

void main() {
  test('the site publishes the schema the engine gives (UX-02)', () {
    final published = File('../../site/public/schema/workflow-1.json');
    final schema = workflowJsonSchema(StepPlanners(allSteps()));

    expect(
      jsonDecode(published.readAsStringSync()),
      jsonDecode(jsonEncode(schema)),
      reason:
          'Write the file again from workflowJsonSchema when the step types '
          'change.',
    );
    expect(schema[r'$id'], workflowJsonSchemaUrl);
  });

  group('a step', () {
    const catalog = MapStepCatalog(
      {
        'build.ios': {'exportOptionsPlist', 'obfuscate', 'extra'},
        'version.bump': {},
      },
      typed: {
        'build.ios': [
          StepKey.needed('exportOptionsPlist', description: 'The plist.'),
          StepKey('obfuscate', value: StepValue.flag, defaultValue: false),
        ],
      },
    );
    final step =
        (workflowJsonSchema(catalog)[r'$defs']! as Map)['step']!
            as Map<String, Object?>;
    final rules = step['allOf']! as List<Object?>;

    Map<String, Object?> then(String kind) {
      final rule = rules.cast<Map<String, Object?>>().singleWhere((rule) {
        final kinds = (rule['if']! as Map)['properties']! as Map;
        return (kinds['kind']! as Map)['const'] == kind;
      });
      return rule['then']! as Map<String, Object?>;
    }

    test('names the step types of the catalog', () {
      expect((step['properties']! as Map)['kind'], {
        'enum': ['build.ios', 'version.bump'],
      });
    });

    test('needs "with" when its type needs a key, and types each key', () {
      final ios = then('build.ios');
      final keys =
          ((ios['properties']! as Map)['with']! as Map)['properties']! as Map;

      expect(ios['required'], ['with']);
      expect(((ios['properties']! as Map)['with']! as Map)['required'], [
        'exportOptionsPlist',
      ]);
      expect(keys['exportOptionsPlist'], {
        'description': 'The plist.',
        'type': 'string',
      });
      expect(keys['obfuscate'], {
        'default': false,
        'anyOf': [
          {'type': 'boolean'},
          {
            'type': 'string',
            'pattern': r'\$\{\{',
            'description': r'A placeholder, such as ${{ inputs.notes }}.',
          },
        ],
      });
      expect(keys['extra'], isEmpty, reason: 'anything goes');
      expect(then('version.bump').containsKey('required'), isFalse);
    });
  });
}
