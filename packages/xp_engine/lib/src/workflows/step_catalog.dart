/// The step types a workflow can use, and the keys each takes under `with`.
///
/// The parser checks a document against it; `StepPlanners` is the one the
/// engine uses.
abstract interface class StepCatalog {
  /// The step types, sorted.
  Iterable<String> get kinds;

  /// The keys the step type [kind] takes under `with`, or `null` if there is
  /// no such step type.
  Set<String>? withKeys(String kind);
}

/// A [StepCatalog] over a map, for tests.
class MapStepCatalog implements StepCatalog {
  /// Creates a catalog of the step types in [keys].
  const new(this.keys);

  /// The `with` keys of each step type.
  final Map<String, Set<String>> keys;

  @override
  Iterable<String> get kinds => keys.keys.toList()..sort();

  @override
  Set<String>? withKeys(String kind) => keys[kind];
}
