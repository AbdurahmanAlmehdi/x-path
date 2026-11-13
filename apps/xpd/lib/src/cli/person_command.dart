import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';

/// `xpd person`: manage the people who use the engine (ADR 0017), on the
/// engine machine, without a token. What `xpd token create` is to tokens.
class PersonCommand extends Command<int> {
  /// Creates the command.
  new(this._context) {
    addSubcommand(PersonCreateCommand(_context));
    addSubcommand(PersonListCommand(_context));
  }

  final XpdContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  String get name => 'person';

  @override
  String get description => 'Manage the people who use the engine.';
}

/// `xpd person create`: adds a person and prints their id.
class PersonCreateCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'What the person is called, for example "Sam".',
      )
      ..addOption(
        'role',
        abbr: 'r',
        help: 'What the person may do.',
        allowed: PersonRole.values.map((role) => role.name),
      );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Add a person with a role and print their id.';

  @override
  Future<int> run() async {
    final name = argResults!.option('name');
    final role = argResults!.option('role');
    if (name == null || name.trim().isEmpty) {
      usageException('--name is required and must not be blank.');
    }
    if (role == null) usageException('--role is required.');
    try {
      final person = await withDatabase(
        (database) =>
            _people(database)
                .create(name: name, role: PersonRole.values.byName(role)),
      );
      context.err.writeln(
        'Added ${person.name}, ${person.role.name} (${person.id}).',
      );
      context.out.writeln(person.id);
      return 0;
    } on PersonException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }
  }
}

/// `xpd person list`: prints every person, one per line.
class PersonListCommand extends XpdCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the people, oldest first: id, role, name, and "removed" for '
      'those removed.';

  @override
  Future<int> run() async {
    final people = await withDatabase((database) => _people(database).list());
    for (final person in people) {
      context.out.writeln(
        [
          person.id,
          person.role.name,
          person.name,
          if (person.isRemoved) 'removed',
        ].join('\t'),
      );
    }
    return 0;
  }
}

PersonService _people(SqliteDatabase database) {
  final people = SqlitePersonRepository(database);
  return PersonService(
    people: people,
    tokens: TokenService(
      tokens: SqliteDeviceTokenRepository(database),
      people: people,
      clock: const SystemClock(),
    ),
    clock: const SystemClock(),
  );
}
