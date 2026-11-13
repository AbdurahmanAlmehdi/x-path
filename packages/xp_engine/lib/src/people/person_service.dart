import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/people/person_exceptions.dart';
import 'package:xp_engine/src/people/person_repository.dart';
import 'package:xp_engine/src/tokens/token_service.dart';

/// The longest name a person may have.
const maxPersonNameLength = 80;

/// The people who use the engine, and their roles (ADR 0017).
///
/// **The last admin.** The engine always keeps at least one active admin:
/// demoting or removing the last one is refused with a
/// [PersonConflictException]. Changes run one at a time, so two requests
/// that each demote one of two admins cannot both pass.
///
/// **Names.** Two active people never share a name, ignoring case, because
/// `xpd person code <name>` finds a person by name.
///
/// **Removal** is soft: the person stays, so approvals and runs keep their
/// name, and every token they had is revoked.
class PersonService {
  /// Creates the service.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._people,
    required this._tokens,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  final PersonRepository _people;
  final TokenService _tokens;
  final Clock _clock;
  final Random _random;
  Future<void> _tail = Future.value();

  /// Every person, removed ones included, oldest first.
  Future<List<Person>> list() => _people.list();

  /// The person [id], removed or not.
  ///
  /// Throws a [PersonNotFoundException] if there is none.
  Future<Person> get(String id) async =>
      await _people.get(id) ?? (throw PersonNotFoundException(id));

  /// Adds a person called [name] with [role].
  ///
  /// Throws a [PersonRequestException] for a blank or too long name, and a
  /// [PersonConflictException] if an active person has that name.
  Future<Person> create({required String name, required PersonRole role}) =>
      _locked(() async {
        final trimmed = await _availableName(name);
        final person = Person(
          id: 'per_${_hex(8)}',
          name: trimmed,
          role: role,
          createdAt: _clock.now(),
        );
        await _people.add(person);
        return person;
      });

  /// Renames the active person [id] to [name].
  ///
  /// Throws a [PersonNotFoundException], a [PersonRequestException] and a
  /// [PersonConflictException] as [create] does.
  Future<Person> rename(String id, String name) => _locked(() async {
    final person = await _requireActive(id);
    final renamed = person.copyWith(name: await _availableName(name, id: id));
    await _people.update(renamed);
    return renamed;
  });

  /// Gives the active person [id] the [role]. It applies to their next
  /// request.
  ///
  /// Throws a [PersonNotFoundException], and a [PersonConflictException] when
  /// it would demote the last admin.
  Future<Person> setRole(String id, PersonRole role) => _locked(() async {
    final person = await _requireActive(id);
    if (role != PersonRole.admin) {
      await _requireAnotherAdmin(person, 'demote');
    }
    final changed = person.copyWith(role: role);
    await _people.update(changed);
    return changed;
  });

  /// Removes the active person [id] and revokes every token they have.
  ///
  /// Throws a [PersonNotFoundException], and a [PersonConflictException] for
  /// the last admin.
  Future<Person> remove(String id) => _locked(() async {
    final person = await _requireActive(id);
    await _requireAnotherAdmin(person, 'remove');
    final removed = person.copyWith(removedAt: _clock.now());
    await _people.update(removed);
    await _tokens.revokeAllOf(id);
    return removed;
  });

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Person> _requireActive(String id) async {
    final person = await _people.get(id);
    if (person == null || person.isRemoved) throw PersonNotFoundException(id);
    return person;
  }

  Future<void> _requireAnotherAdmin(Person person, String what) async {
    if (person.role != PersonRole.admin) return;
    final admins = (await _people.list()).where(
      (other) => !other.isRemoved && other.role == PersonRole.admin,
    );
    if (admins.length == 1) {
      throw PersonConflictException(
        'Cannot $what ${person.name}: they are the last admin. Make someone '
        'else an admin first.',
      );
    }
  }

  /// [name] trimmed, once it is valid and no other active person has it.
  Future<String> _availableName(String name, {String? id}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxPersonNameLength) {
      throw const PersonRequestException(
        'A name has 1 to $maxPersonNameLength characters.',
      );
    }
    final taken = (await _people.list()).any(
      (other) =>
          other.id != id &&
          !other.isRemoved &&
          other.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (taken) {
      throw PersonConflictException('Someone is called $trimmed already.');
    }
    return trimmed;
  }

  String _hex(int length) => List.generate(
    length,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
