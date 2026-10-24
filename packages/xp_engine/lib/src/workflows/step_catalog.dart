import 'package:xp_api/xp_api.dart';

/// What a key of `with` holds.
enum StepValue {
  /// A string.
  text('a string', StepKeyType.string),

  /// `true` or `false`.
  flag('true or false', StepKeyType.boolean),

  /// A number.
  number('a number', StepKeyType.number),

  /// A list of strings.
  texts('a list of strings', StepKeyType.list),

  /// A mapping of strings to strings.
  textMap('a mapping of strings', StepKeyType.map),

  /// Anything; the step type checks it.
  any('anything', StepKeyType.any);

  new(this.shape, this.wire);

  /// The value in words, as in `"track" must be a string`.
  final String shape;

  /// The type the schema gives editors.
  final StepKeyType wire;

  /// Whether [given] is such a value.
  bool fits(Object? given) => switch (this) {
    text => given is String,
    flag => given is bool,
    number => given is num,
    texts => given is List && given.every((item) => item is String),
    textMap => given is Map && given.values.every((item) => item is String),
    any => true,
  };
}

/// A key a step type takes under `with`.
class StepKey {
  /// Creates the key [name], holding [value].
  const new(
    this.name, {
    this.value = StepValue.text,
    this.description = '',
    this.defaultValue,
  }) : required = false,
       options = null;

  /// Creates a key the step cannot do without.
  const new needed(
    this.name, {
    this.value = StepValue.text,
    this.description = '',
  }) : required = true,
       options = null,
       defaultValue = null;

  /// Creates a key that takes one of [options], or a list of them.
  const new choice(
    this.name,
    this.options, {
    this.value = StepValue.text,
    this.description = '',
    this.defaultValue,
  }) : required = false;

  /// Its name under `with`.
  final String name;

  /// What it holds.
  final StepValue value;

  /// Whether a step of its type must give it.
  final bool required;

  /// The strings it may take, when they are fixed.
  final List<String>? options;

  /// What it is for, in a sentence.
  final String description;

  /// What the step uses when it is not given, when that is one value.
  final Object? defaultValue;

  /// The key as the schema gives it to editors.
  StepKeySchema toWire() => StepKeySchema(
    name: name,
    type: value.wire,
    required: required,
    defaultValue: defaultValue,
    options: options,
    description: description,
  );

  /// What is wrong with [given] for this key, as in `"track" must be a
  /// string`, or `null` when it fits. A string with a placeholder is only
  /// known at dispatch, so it fits here.
  String? problemOf(Object? given) {
    if (given is String && given.contains(r'${{')) return null;
    if (!value.fits(given)) return '"$name" must be ${value.shape}';
    bool allowed(Object? item) =>
        item is String && (item.contains(r'${{') || options!.contains(item));
    final items = given is List ? given : [given];
    if (options == null || items.every(allowed)) return null;
    return '"$name" takes ${options!.join(', ')}';
  }
}

/// The step types a workflow can use, and the keys each takes under `with`.
///
/// The parser checks a document against it; `StepPlanners` is the one the
/// engine uses.
abstract interface class StepCatalog {
  /// The step types, sorted.
  Iterable<String> get kinds;

  /// The names of the keys the step type [kind] takes under `with`, or
  /// `null` if there is no such step type.
  Set<String>? withKeys(String kind);

  /// The keys the step type [kind] takes under `with`, by name, or `null` if
  /// there is no such step type.
  Map<String, StepKey>? keysOf(String kind);

  /// The step type [kind] as the schema gives it to editors, or `null` if
  /// there is no such step type.
  StepType? describe(String kind);
}

/// A [StepCatalog] over a map, for tests.
class MapStepCatalog implements StepCatalog {
  /// Creates a catalog of the step types in [keys], each key a string, and
  /// the [typed] keys of some of them.
  const new(this.keys, {this.typed = const {}});

  /// The `with` keys of each step type.
  final Map<String, Set<String>> keys;

  /// The keys of the step types that say more than a name.
  final Map<String, List<StepKey>> typed;

  @override
  Iterable<String> get kinds => keys.keys.toList()..sort();

  @override
  Set<String>? withKeys(String kind) => keys[kind];

  @override
  StepType? describe(String kind) => switch (keysOf(kind)) {
    null => null,
    final keys => StepType(
      kind: kind,
      withKeys: keys.keys.toList()..sort(),
      title: kind,
      keys: [for (final key in keys.values) key.toWire()],
    ),
  };

  @override
  Map<String, StepKey>? keysOf(String kind) => keys[kind] == null
      ? null
      : {
          for (final name in keys[kind]!)
            name: StepKey(name, value: StepValue.any),
          for (final key in typed[kind] ?? const <StepKey>[]) key.name: key,
        };
}
