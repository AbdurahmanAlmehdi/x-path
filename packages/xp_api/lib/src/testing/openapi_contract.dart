// The development dependencies of this package are enough: only tests import
// this library.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `openapi.yaml` as a checker for real responses.
///
/// Used by the `contract` tests of this package and of `xpd`:
///
/// ```dart
/// final contract = await OpenApiContract.load();
/// final response = await client.get(uri);
/// contract.expectResponse(
///   method: 'GET',
///   path: '/health',
///   statusCode: response.statusCode,
///   contentType: response.headers['content-type'],
///   body: response.body,
/// );
/// ```
///
/// Supports what the spec uses: path templates, `$ref` into
/// `#/components/responses`, JSON bodies validated as JSON Schema 2020-12
/// (OpenAPI 3.1 schemas are JSON Schema), and `4XX`/`default` responses.
class OpenApiContract {
  /// Reads a contract from the YAML [source] of an OpenAPI 3.1 document.
  new parse(String source)
    : _document = _toPlain(loadYaml(source))! as Map<String, dynamic>;

  /// Reads the `openapi.yaml` that ships with this package.
  static Future<OpenApiContract> load() async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:xp_api/xp_api.dart'),
    );
    final file = File.fromUri(library!.resolve('../openapi.yaml'));
    return OpenApiContract.parse(await file.readAsString());
  }

  final Map<String, dynamic> _document;

  /// The problems that make a response differ from the contract: none when
  /// it matches.
  ///
  /// [path] is the concrete path (`/projects/p1`), [body] the raw body text
  /// and [contentType] the `content-type` header, if any.
  List<String> validateResponse({
    required String method,
    required String path,
    required int statusCode,
    required String body,
    String? contentType,
  }) {
    final label = '${method.toUpperCase()} $path';
    final operation = _findOperation(method, path);
    if (operation == null) return ['$label is not in openapi.yaml'];

    final responses = operation['responses'] as Map<String, dynamic>;
    final declared =
        responses['$statusCode'] ??
        responses['${statusCode ~/ 100}XX'] ??
        responses['default'];
    if (declared == null) {
      return ['$label does not declare status $statusCode'];
    }
    final response = _resolve(declared as Map<String, dynamic>);

    final content = response['content'] as Map<String, dynamic>?;
    if (content == null) {
      return body.isEmpty
          ? const []
          : ['$label $statusCode declares no body but got one'];
    }
    final media = content['application/json'] as Map<String, dynamic>?;
    if (media == null) return const [];
    if (contentType == null || !contentType.startsWith('application/json')) {
      return ['$label $statusCode expects application/json, got $contentType'];
    }
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      return ['$label $statusCode body is not JSON: ${e.message}'];
    }
    return [
      for (final problem in _validate(media['schema'], json))
        '$label $statusCode: $problem',
    ];
  }

  /// The problems of [json] against the component schema called [name].
  List<String> validateSchema(String name, Object? json) =>
      _validate({r'$ref': '#/components/schemas/$name'}, json);

  /// Fails the test with every problem [validateResponse] finds.
  void expectResponse({
    required String method,
    required String path,
    required int statusCode,
    required String body,
    String? contentType,
  }) {
    final problems = validateResponse(
      method: method,
      path: path,
      statusCode: statusCode,
      body: body,
      contentType: contentType,
    );
    if (problems.isNotEmpty) {
      fail('Response differs from openapi.yaml:\n${problems.join('\n')}');
    }
  }

  Map<String, dynamic>? _findOperation(String method, String path) {
    final paths = _document['paths'] as Map<String, dynamic>;
    for (final entry in paths.entries) {
      if (_matches(entry.key, path)) {
        return (entry.value as Map<String, dynamic>)[method.toLowerCase()]
            as Map<String, dynamic>?;
      }
    }
    return null;
  }

  bool _matches(String template, String path) {
    final pattern = template
        .split('/')
        .map(
          (segment) => segment.startsWith('{') && segment.endsWith('}')
              ? '[^/]+'
              : RegExp.escape(segment),
        )
        .join('/');
    return RegExp('^$pattern\$').hasMatch(path);
  }

  Map<String, dynamic> _resolve(Map<String, dynamic> node) {
    final ref = node[r'$ref'] as String?;
    if (ref == null) return node;
    var target = _document as Object?;
    for (final key in ref.substring('#/'.length).split('/')) {
      target = (target! as Map<String, dynamic>)[key];
    }
    return target! as Map<String, dynamic>;
  }

  List<String> _validate(Object? schema, Object? json) {
    // Only component schemas become JSON Schema `$defs`: the rest of
    // `components` (security schemes, responses) is not JSON Schema.
    final components = _document['components'] as Map<String, dynamic>;
    final root = <String, dynamic>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$defs': _rewriteRefs(components['schemas']),
      ...(_rewriteRefs(schema)! as Map<String, dynamic>),
    };
    final results = JsonSchema.create(
      root,
      schemaVersion: SchemaVersion.draft2020_12,
    ).validate(json, validateFormats: true);
    return [for (final error in results.errors) error.toString()];
  }
}

/// Points `#/components/schemas/X` references at `#/$defs/X`.
Object? _rewriteRefs(Object? node) => switch (node) {
  final Map<String, dynamic> map => {
    for (final entry in map.entries)
      entry.key: entry.key == r'$ref'
          ? (entry.value as String).replaceFirst(
              '#/components/schemas/',
              r'#/$defs/',
            )
          : _rewriteRefs(entry.value),
  },
  final List<dynamic> list => list.map(_rewriteRefs).toList(),
  _ => node,
};

/// YAML collections to plain `Map<String, dynamic>` / `List`, which is what
/// `json_schema` and the casts above expect.
Object? _toPlain(Object? node) => switch (node) {
  final YamlMap map => {
    for (final entry in map.entries) entry.key as String: _toPlain(entry.value),
  },
  final YamlList list => [for (final item in list) _toPlain(item)],
  _ => node,
};
