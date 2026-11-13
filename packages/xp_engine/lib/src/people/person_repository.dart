import 'package:xp_api/xp_api.dart';

/// Where people are kept (ADR 0017).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class PersonRepository {
  /// Every person, removed ones included, oldest first.
  Future<List<Person>> list();

  /// The person [id], removed or not, or `null`.
  Future<Person?> get(String id);

  /// Stores [person], who is new.
  Future<void> add(Person person);

  /// Replaces the stored person with the id of [person].
  Future<void> update(Person person);
}

/// A [PersonRepository] that forgets everything on exit.
class InMemoryPersonRepository implements PersonRepository {
  /// Creates the repository with [people] in it.
  new([Iterable<Person> people = const []]) {
    for (final person in people) {
      _people[person.id] = person;
    }
  }

  final _people = <String, Person>{};

  @override
  Future<List<Person>> list() async => List.unmodifiable(_people.values);

  @override
  Future<Person?> get(String id) async => _people[id];

  @override
  Future<void> add(Person person) async => _people[person.id] = person;

  @override
  Future<void> update(Person person) async => _people[person.id] = person;
}
