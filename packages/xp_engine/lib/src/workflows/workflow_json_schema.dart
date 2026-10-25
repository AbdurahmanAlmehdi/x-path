import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/step_catalog.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';

/// Where the site publishes [workflowJsonSchema], for editors to complete
/// workflow documents (`# yaml-language-server: $schema=...`).
const workflowJsonSchemaUrl =
    'https://xpath.abdurahman.ly/schema/workflow-1.json';

/// Workflow documents (schema 1) as a JSON Schema, with the step types of
/// [catalog] and their keys, for editors. The engine's check
/// (`WorkflowParser`) is still the one that decides: an expression, a job id
/// used twice or `commitFrom` are beyond a JSON Schema.
Map<String, Object?> workflowJsonSchema(StepCatalog catalog) {
  const placeholder = {
    'type': 'string',
    'pattern': r'\$\{\{',
    'description': r'A placeholder, such as ${{ inputs.notes }}.',
  };
  const text = {'type': 'string', 'minLength': 1};
  Map<String, Object?> listOf(Map<String, Object?> item) => {
    'anyOf': [
      {'type': 'array', 'items': item},
      placeholder,
    ],
  };

  Map<String, Object?> keySchema(StepKey key) {
    final values = {'enum': ?key.options};
    final typed = switch (key.value) {
      StepValue.text => {'type': 'string', ...values},
      StepValue.flag => {'type': 'boolean'},
      StepValue.number => {'type': 'number'},
      StepValue.texts => {
        'type': 'array',
        'items': {'type': 'string', ...values},
      },
      StepValue.textMap => {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      },
      StepValue.any => <String, Object?>{},
    };
    return {
      if (key.description.isNotEmpty) 'description': key.description,
      'default': ?key.defaultValue,
      ...switch (key.value) {
        StepValue.any => typed,
        StepValue.text when key.options == null => typed,
        _ => {
          'anyOf': [typed, placeholder],
        },
      },
    };
  }

  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': workflowJsonSchemaUrl,
    'title': 'XPath workflow',
    'description':
        'A workflow document, schema $workflowSchemaVersion: stages that run '
        'in order, each with jobs that run in parallel.',
    'type': 'object',
    'required': ['schema', 'stages'],
    'additionalProperties': false,
    'properties': {
      'schema': {'const': workflowSchemaVersion},
      'name': text,
      'description': text,
      'lock': {
        'const': 'project',
        'description': 'One run at a time per project.',
      },
      'inputs': {
        'type': 'object',
        'description': 'The variables a dispatch can set (inputs.<name>).',
        'propertyNames': {'pattern': r'^[A-Za-z_][A-Za-z0-9_]*$'},
        'additionalProperties': {
          'anyOf': [
            {'type': 'null'},
            {r'$ref': r'#/$defs/input'},
          ],
        },
      },
      'stages': {
        'type': 'array',
        'minItems': 1,
        'items': {r'$ref': r'#/$defs/stage'},
      },
    },
    r'$defs': {
      'input': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'description': text,
          'type': {
            'enum': ['string', 'boolean', 'choice', 'json', 'release'],
          },
          'options': {
            'type': 'array',
            'minItems': 1,
            'items': {'type': 'string'},
          },
          'default': <String, Object?>{},
          'required': {'type': 'boolean'},
        },
      },
      'stage': {
        'type': 'object',
        'required': ['name', 'jobs'],
        'additionalProperties': false,
        'properties': {
          'name': text,
          'jobs': {
            'type': 'object',
            'minProperties': 1,
            'propertyNames': {'pattern': r'^[A-Za-z][A-Za-z0-9_-]*$'},
            'additionalProperties': {r'$ref': r'#/$defs/job'},
          },
        },
      },
      'job': {
        'type': 'object',
        'required': ['steps'],
        'additionalProperties': false,
        'properties': {
          'name': text,
          'matrix': {
            'type': 'object',
            'minProperties': 1,
            'additionalProperties': false,
            'properties': {
              'platform': listOf({'enum': platformNames}),
              'flavor': listOf({'type': 'string'}),
            },
          },
          'if': {r'$ref': r'#/$defs/condition'},
          'capabilities': {
            'type': 'array',
            'items': {
              'enum': [
                for (final capability in Capability.named) capability.wire,
              ],
            },
          },
          'steps': {
            'type': 'array',
            'minItems': 1,
            'items': {r'$ref': r'#/$defs/step'},
          },
        },
      },
      'condition': {
        'type': 'string',
        'minLength': 1,
        'description':
            "An expression, such as platform == 'android' && flavor.prod.",
      },
      'step': {
        'type': 'object',
        'required': ['kind'],
        'additionalProperties': false,
        'properties': {
          'kind': {'enum': catalog.kinds.toList()},
          'with': {'type': 'object'},
          'if': {r'$ref': r'#/$defs/condition'},
          'gate': {
            'enum': [for (final action in GateAction.values) action.wire],
          },
        },
        'allOf': [
          for (final kind in catalog.kinds)
            if (catalog.keysOf(kind)! case final keys)
              {
                'if': {
                  'properties': {
                    'kind': {'const': kind},
                  },
                },
                'then': {
                  if (keys.values.any((key) => key.required))
                    'required': ['with'],
                  'properties': {
                    'kind': {
                      if (catalog.describe(kind)!.description case final about
                          when about.isNotEmpty)
                        'description': about,
                    },
                    'with': {
                      'type': 'object',
                      'additionalProperties': false,
                      'properties': {
                        for (final key in keys.values) key.name: keySchema(key),
                      },
                      'required': [
                        for (final key in keys.values)
                          if (key.required) key.name,
                      ],
                    },
                  },
                },
              },
        ],
      },
    },
  };
}
