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
    addSubcommand(PersonCodeCommand(_context));
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

/// `xpd person create`: adds a person, prints their id, and tells a sign-in
/// code for the web dashboard (D8), so the first admin of a headless engine
/// can sign in.
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
  String get description =>
      'Add a person with a role, print their id and a sign-in code for the '
      'web dashboard.';

  @override
  Future<int> run() async {
    final name = argResults!.option('name');
    final role = argResults!.option('role');
    if (name == null || name.trim().isEmpty) {
      usageException('--name is required and must not be blank.');
    }
    if (role == null) usageException('--role is required.');
    try {
      final (person, code, publicUrl) = await withDatabase((database) async {
        // The engine machine's user owns the data directory: no token.
        final person = await _people(database)
            .create(name: name, role: PersonRole.values.byName(role), by: null);
        final publicUrl = await _publicUrl(database);
        return (person, await _signIn(database).issue(person.id), publicUrl);
      });
      context.err.writeln(
        'Added ${person.name}, ${person.role.name} (${person.id}).',
      );
      _tellCode(context, person, code, publicUrl);
      context.out.writeln(person.id);
      return 0;
    } on PersonException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }
  }
}

/// `xpd person code <name or id>`: issues a new sign-in code for the web
/// dashboard (D8) and prints it. The person's unused codes stop working.
class PersonCodeCommand extends XpdCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'code';

  @override
  String get description =>
      'Issue a sign-in code for the web dashboard and print it. It works '
      'once, for 10 minutes.';

  @override
  String get invocation => 'xpd person code <name or id>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Give one name or person id.');
    final wanted = rest.single.trim();
    final issued = await withDatabase((database) async {
      final person = await _people(database).findActive(wanted);
      if (person == null) return null;
      final publicUrl = await _publicUrl(database);
      return (person, await _signIn(database).issue(person.id), publicUrl);
    });
    if (issued == null) {
      context.err.writeln(
        'xpd: There is no active person "$wanted". See: xpd person list',
      );
      return 1;
    }
    final (person, code, publicUrl) = issued;
    _tellCode(context, person, code, publicUrl);
    context.out.writeln(code.code);
    return 0;
  }
}

/// Tells, on standard error, how [person] signs in with [code]: with a
/// link on the [publicUrl] when one is set, the code in its fragment, which
/// a browser never sends to a server.
void _tellCode(
  XpdContext context,
  Person person,
  SignInCode code,
  String? publicUrl,
) {
  context.err.writeln(
    'Sign-in code for ${person.name}: ${code.code}. It works once, until '
    '${code.expiresAt.toIso8601String()}. Enter it on the sign-in page of '
    'the dashboard (/sign-in) on this machine, or through the public URL.',
  );
  if (publicUrl != null) {
    context.err.writeln(
      'Or open the link, which signs in with it: '
      '${code.signInUrl(Uri.parse(publicUrl))}',
    );
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

PersonService _people(SqliteDatabase database) => PersonService(
  people: SqlitePersonRepository(database),
  tokens: tokenServiceOf(database),
  clock: const SystemClock(),
);

SignInCodeService _signIn(SqliteDatabase database) => SignInCodeService(
  codes: SqliteSignInCodeRepository(database),
  people: SqlitePersonRepository(database),
  tokens: tokenServiceOf(database),
  clock: const SystemClock(),
);

Future<String?> _publicUrl(SqliteDatabase database) =>
    PublicUrlService(settings: SqliteEngineSettingRepository(database))
        .origin();
