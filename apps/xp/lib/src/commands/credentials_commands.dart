import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp credentials`: the named credentials of the engine, which any flavor of
/// any project may use (one per kind).
///
/// A secret is never an argument: it is asked for at the terminal with the
/// echo off, or read from standard input with a `--*-stdin` option. Nothing
/// prints it.
XpGroup credentialsCommand(XpContext context) => XpGroup(
  context,
  'credentials',
  'Add, check and assign the named credentials the flavors use.',
  [
    CredentialsListCommand(context),
    CredentialsShowCommand(context),
    CredentialsAddCommand(context),
    CredentialsRenameCommand(context),
    CredentialsReplaceCommand(context),
    CredentialsVerifyCommand(context),
    CredentialsRemoveCommand(context),
    CredentialsAssignCommand(context),
    CredentialsUnassignCommand(context),
  ],
  aliases: const ['credential'],
);

/// `xp credentials list`.
class CredentialsListCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the credentials, with how many flavors use each.';

  @override
  Future<int> execute(XpClient client) async {
    final credentials = await client.listNamedCredentials();
    emit([for (final credential in credentials) credential.toJson()], () {
      if (credentials.isEmpty) {
        return 'No credentials. Add one: '
            'xp credentials add --kind <kind> --name <name> ...';
      }
      return renderTable(
        ['ID', 'NAME', 'KIND', 'ACCOUNT', 'STATUS', 'USED BY'],
        [
          for (final credential in credentials)
            [
              credential.id,
              credential.name,
              credential.kind.wire,
              credential.account ?? '-',
              credential.status.wire,
              _flavors(credential.usedBy.length),
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// `xp credentials show <credential>`.
class CredentialsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description =>
      'Show a credential and every flavor that uses it, with its checks.';

  @override
  String get invocation => 'xp credentials show <credential>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final credential = await resolveCredential(client, reference);
    emit(credential.toJson(), () => describeCredential(credential));
    return XpExit.ok;
  }
}

/// `xp credentials add --kind <kind> --name <name> [options of the kind]`.
class CredentialsAddCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'kind',
        help:
            'What it is for: '
            '${_namedKinds.map((kind) => kind.wire).join(', ')}.',
        valueHelp: 'kind',
      )
      ..addOption(
        'name',
        help: 'Its name, unique regardless of case.',
        valueHelp: 'name',
      );
    _addMaterialOptions(argParser);
  }

  @override
  String get name => 'add';

  @override
  String get description =>
      'Add a credential. The engine checks it first and stores it only if '
      'the store or tool accepts it.';

  @override
  String get invocation =>
      'xp credentials add --kind <kind> --name <name> [options of the kind]';

  @override
  String get usageFooter => _secretsFooter;

  @override
  Future<int> execute(XpClient client) async {
    positionals([]);
    final kind = _kind(argResults!.option('kind'));
    final name = _name(
      this,
      argResults!.option('name') ?? usageException('Missing --name.'),
    );
    final material = await _material(this, kind);
    final credential = await client.createCredential(
      CreateCredentialRequest(name: name, kind: kind, material: material),
    );
    emit(
      credential.toJson(),
      () =>
          'Added "${credential.name}".\n\n'
          '${describeCredential(credential)}',
    );
    return XpExit.ok;
  }

  CredentialKind _kind(String? wire) {
    if (wire == null) {
      usageException(
        'Missing --kind (${_namedKinds.map((k) => k.wire).join(', ')}).',
      );
    }
    final kind = CredentialKind.fromWire(wire);
    if (kind == CredentialKind.github) usageException(_githubHint);
    if (kind == null) {
      usageException(
        'Unknown --kind "$wire". Use one of: '
        '${_namedKinds.map((k) => k.wire).join(', ')}.',
      );
    }
    return kind;
  }
}

/// `xp credentials rename <credential> <new name>`.
class CredentialsRenameCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'rename';

  @override
  String get description =>
      'Rename a credential. Its id and the flavors that use it stay.';

  @override
  String get invocation => 'xp credentials rename <credential> <new name>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference, newName] = positionals(['credential', 'new name']);
    final name = _name(this, newName);
    final credential = await resolveCredential(client, reference);
    final renamed = await client.renameCredential(credential.id, name);
    emit(
      renamed.toJson(),
      () =>
          'Renamed "${credential.name}" to "${renamed.name}" (${renamed.id}).',
    );
    return XpExit.ok;
  }
}

/// `xp credentials replace <credential> [options of its kind]`.
class CredentialsReplaceCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    _addMaterialOptions(argParser);
  }

  @override
  String get name => 'replace';

  @override
  String get description =>
      'Give a credential a new secret. The name, the id and the flavors that '
      'use it stay; the engine checks the new secret first.';

  @override
  String get invocation =>
      'xp credentials replace <credential> [options of its kind]';

  @override
  String get usageFooter => _secretsFooter;

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final credential = await resolveCredential(client, reference);
    final material = await _material(this, credential.kind);
    final replaced = await client.replaceCredentialSecret(
      credential.id,
      ReplaceCredentialRequest(material),
    );
    emit(
      replaced.toJson(),
      () =>
          'Replaced the secret of "${replaced.name}".\n\n'
          '${describeCredential(replaced)}',
    );
    return XpExit.ok;
  }
}

/// `xp credentials verify <credential>`.
class CredentialsVerifyCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Check a credential and every flavor that uses it again. Exits 1 when '
      'a check refuses it.';

  @override
  String get invocation => 'xp credentials verify <credential>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final credential = await client.verifyNamedCredential(
      (await resolveCredential(client, reference)).id,
    );
    emit(credential.toJson(), () => describeCredential(credential));
    final refused =
        credential.status == CredentialStatus.rejected ||
        credential.usedBy.any(
          (usage) => usage.status == CredentialStatus.rejected,
        );
    return refused ? XpExit.failed : XpExit.ok;
  }
}

/// `xp credentials remove <credential> [--force]`.
class CredentialsRemoveCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Remove it from every flavor that uses it, then delete it.',
    );
  }

  @override
  String get name => 'remove';

  @override
  String get description =>
      'Delete a credential. One that flavors use is deleted only with '
      '--force.';

  @override
  String get invocation => 'xp credentials remove <credential> [--force]';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final force = argResults!.flag('force');
    final credential = await resolveCredential(client, reference);
    try {
      await client.deleteNamedCredential(credential.id, force: force);
    } on ApiException catch (error) {
      if (!error.isCredentialInUse) rethrow;
      logger.err(_inUse(credential, error.usedBy));
      return XpExit.conflict;
    }
    final unassigned = force ? credential.usedBy.length : 0;
    emit(
      {'removed': credential.id, 'name': credential.name},
      () => unassigned == 0
          ? 'Deleted "${credential.name}" (${credential.id}).'
          : 'Removed "${credential.name}" from ${_flavors(unassigned)} and '
                'deleted it (${credential.id}).',
    );
    return XpExit.ok;
  }

  String _inUse(NamedCredential credential, List<CredentialUsage> usedBy) {
    final name = credential.name;
    final usages = renderTable(
      ['PROJECT', 'APP', 'FLAVOR'],
      [
        for (final usage in usedBy)
          [usage.project ?? usage.projectId, usage.app, usage.flavor],
      ],
    );
    return '"$name" is used by ${_flavors(usedBy.length)}, so it was not '
        'deleted:\n$usages\n'
        'Remove it from them and delete it: '
        'xp credentials remove "$name" --force';
  }
}

/// `xp credentials assign`: see [CredentialsAssignCommand.invocation].
class CredentialsAssignCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    _addFlavorOptions(argParser, 'The flavor that uses it.');
    argParser
      ..addFlag(
        'all-flavors',
        negatable: false,
        help:
            'Every flavor of the app uses it. A flavor that has another '
            'credential of the kind keeps it, unless --replace.',
      )
      ..addFlag(
        'replace',
        negatable: false,
        help:
            'With --all-flavors: the flavors that have another credential of '
            'the kind use this one instead.',
      );
  }

  @override
  String get name => 'assign';

  @override
  String get description =>
      'Make a flavor, or every flavor of an app, use a credential for its '
      'kind.';

  @override
  String get invocation =>
      'xp credentials assign <credential> --project <project> '
      '(--flavor <flavor> | --all-flavors) [--app <path>] [--replace]';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final args = argResults!;
    final projectReference = _project(this);
    final app = args.option('app')!;
    final flavor = args.option('flavor');
    final allFlavors = args.flag('all-flavors');
    final replace = args.flag('replace');
    if (flavor != null && allFlavors) {
      usageException('Give --flavor or --all-flavors, not both.');
    }
    if (flavor == null && !allFlavors) {
      usageException('Missing --flavor (or --all-flavors).');
    }
    if (replace && !allFlavors) {
      usageException('--replace goes with --all-flavors.');
    }
    final credential = await resolveCredential(client, reference);
    final projectId = await resolveProject(client, projectReference);

    var from = flavor;
    if (from == null) {
      // Every flavor of the app: the engine needs one flavor to assign from,
      // and that one always gets the credential. Pick one that has no other
      // credential of the kind, so nothing is replaced unless --replace.
      final flavors = await _flavorsOf(client, projectId, app);
      final current = {
        for (final assigned in await client.listCredentials(
          projectId,
          app: app,
        ))
          if (assigned.kind == credential.kind && assigned.app == app)
            assigned.flavor: assigned,
      };
      final free = [
        for (final name in flavors)
          if (current[name] == null || current[name]!.id == credential.id) name,
      ];
      if (free.isEmpty && !replace) {
        final response = AssignCredentialResponse(
          assigned: const [],
          kept: [for (final name in flavors) current[name]!],
        );
        emit(response.toJson(), () => _describe(credential, response));
        return XpExit.ok;
      }
      from = replace ? flavors.first : free.first;
    }

    final response = await client.assignCredential(
      projectId,
      app: app,
      flavor: from,
      kind: credential.kind,
      request: AssignCredentialRequest(
        credentialId: credential.id,
        allFlavors: allFlavors,
        replace: replace,
      ),
    );
    emit(response.toJson(), () => _describe(credential, response));
    return XpExit.ok;
  }

  String _describe(NamedCredential credential, AssignCredentialResponse r) {
    final kind = credential.kind.wire;
    final count = _flavors(r.assigned.length);
    return [
      if (r.assigned.isEmpty)
        'Nothing changed: every flavor has its own $kind credential.'
      else ...[
        'Assigned "${credential.name}" ($kind) to $count:',
        renderTable(
          ['APP', 'FLAVOR', 'STATUS', 'MESSAGE'],
          [
            for (final assigned in r.assigned)
              [
                assigned.app,
                assigned.flavor,
                assigned.status.wire,
                _note(assigned.message, assigned.fix),
              ],
          ],
        ),
      ],
      if (r.kept.isNotEmpty) ...[
        '',
        'Kept their own $kind credential (pass --replace to change them):',
        renderTable(
          ['APP', 'FLAVOR', 'CREDENTIAL'],
          [
            for (final kept in r.kept)
              [kept.app, kept.flavor, kept.name ?? kept.id],
          ],
        ),
      ],
    ].join('\n');
  }
}

/// `xp credentials unassign`: see [CredentialsUnassignCommand.invocation].
class CredentialsUnassignCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    _addFlavorOptions(argParser, 'The flavor that stops using it.');
  }

  @override
  String get name => 'unassign';

  @override
  String get description =>
      'Make a flavor stop using a credential. The credential stays.';

  @override
  String get invocation =>
      'xp credentials unassign <credential> --project <project> '
      '--flavor <flavor> [--app <path>]';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['credential']);
    final args = argResults!;
    final projectReference = _project(this);
    final app = args.option('app')!;
    final flavor = args.option('flavor') ?? usageException('Missing --flavor.');
    final credential = await resolveCredential(client, reference);
    final projectId = await resolveProject(client, projectReference);
    final uses =
        (await client.listCredentials(projectId, app: app, flavor: flavor)).any(
          (assigned) =>
              assigned.id == credential.id &&
              assigned.kind == credential.kind &&
              assigned.app == app &&
              assigned.flavor == flavor,
        );
    if (!uses) {
      throw ReferenceException(
        'The flavor "$flavor" of the app "$app" does not use '
        '"${credential.name}". See: xp credentials show "${credential.name}"',
        notFound: true,
      );
    }
    await client.unassignCredential(
      projectId,
      app: app,
      flavor: flavor,
      kind: credential.kind,
    );
    emit(
      {
        'unassigned': credential.id,
        'projectId': projectId,
        'app': app,
        'flavor': flavor,
        'kind': credential.kind.wire,
      },
      () =>
          'The flavor "$flavor" of the app "$app" no longer uses '
          '"${credential.name}"; it has no ${credential.kind.label} now.',
    );
    return XpExit.ok;
  }
}

/// The lines `xp credentials show` prints.
String describeCredential(NamedCredential credential) {
  final checked = credential.checkedAt;
  final when = checked == null ? '' : ' (checked ${formatTime(checked)})';
  final lines = [
    '${credential.name} (${credential.id})',
    'kind:     ${credential.kind.label} (${credential.kind.wire})',
    'account:  ${credential.account ?? '-'}',
    'status:   ${credential.status.wire}$when',
    if (credential.message case final message?) 'message:  $message',
    if (credential.fix case final fix?) 'fix:      $fix',
    '',
    if (credential.usedBy.isEmpty)
      'No flavor uses it. Assign it: xp credentials assign '
          '"${credential.name}" --project <project> --flavor <flavor>'
    else ...[
      'used by:',
      renderTable(
        ['PROJECT', 'APP', 'FLAVOR', 'STATUS', 'MESSAGE'],
        [
          for (final usage in credential.usedBy)
            [
              usage.project ?? usage.projectId,
              usage.app,
              usage.flavor,
              usage.status.wire,
              _note(usage.message, usage.fix),
            ],
        ],
      ),
    ],
  ];
  return lines.join('\n');
}

/// What a check said and what to do, or `-`.
String _note(String? message, String? fix) {
  final parts = [?message, if (fix != null) 'fix: $fix'];
  return parts.isEmpty ? '-' : parts.join(' ');
}

String _flavors(int count) => '$count flavor${count == 1 ? '' : 's'}';

/// The kinds a named credential can have: every kind but `github`.
final List<CredentialKind> _namedKinds = [
  for (final kind in CredentialKind.values)
    if (kind.isNamed) kind,
];

const _githubHint =
    'The GitHub token is not a named credential: the engine has one, shared '
    'by every project. Set it in the XPath app under Settings, or on the '
    'engine machine run: xpd secrets import-gh';

/// [name] without the blanks around it, if it can name a credential.
String _name(XpCommand command, String name) {
  try {
    return credentialName(name);
  } on FormatException catch (error) {
    command.usageException(error.message.replaceFirst('"name"', 'The name'));
  }
}

/// `--project`, `--app` and `--flavor` of `assign` and `unassign`.
void _addFlavorOptions(ArgParser parser, String flavorHelp) {
  parser
    ..addOption(
      'project',
      help: 'The project: id (prj_...), owner/name or name.',
      valueHelp: 'project',
    )
    ..addOption(
      'app',
      help: 'The app, by its path in the repository.',
      valueHelp: 'path',
      defaultsTo: '.',
    )
    ..addOption('flavor', help: flavorHelp, valueHelp: 'flavor');
}

String _project(XpCommand command) =>
    command.argResults!.option('project') ??
    command.usageException('Missing --project.');

/// The flavors of the app at [app] of the project [projectId].
Future<List<String>> _flavorsOf(
  XpClient client,
  String projectId,
  String app,
) async {
  final project = await client.getProject(projectId);
  for (final profile in project.profile.apps) {
    if (profile.path == app && profile.flavors.isNotEmpty) {
      return [for (final flavor in profile.flavors) flavor.name];
    }
  }
  throw ReferenceException(
    'No app with flavors at "$app" in ${project.fullName}. Apps: '
    '${project.profile.apps.map((profile) => profile.path).join(', ')}',
    notFound: true,
  );
}

// ------------------------------------------------------------ the material

/// A secret field of a kind: never an argument, asked for at the terminal or
/// read from standard input with [stdinOption].
class _Secret {
  const new(this.field, this.label, this.stdinOption, {this.optional = false});

  /// Its key in the material.
  final String field;

  /// What the prompt asks for.
  final String label;

  /// The flag that reads it from standard input.
  final String stdinOption;

  /// Whether it may be left out (the key password of a keystore).
  final bool optional;
}

const _secrets = <CredentialKind, List<_Secret>>{
  CredentialKind.appleId: [
    _Secret('password', 'App-specific password', 'password-stdin'),
  ],
  CredentialKind.keystore: [
    _Secret('storePassword', 'Keystore password', 'store-password-stdin'),
    _Secret(
      'keyPassword',
      'Key password (empty: the keystore password)',
      'key-password-stdin',
      optional: true,
    ),
  ],
  CredentialKind.shorebird: [
    _Secret('token', 'Shorebird API key', 'token-stdin'),
  ],
  CredentialKind.slack: [
    _Secret('webhookUrl', 'Slack webhook URL', 'webhook-url-stdin'),
  ],
};

/// The options of each kind.
const _kindOptions = <CredentialKind, List<String>>{
  CredentialKind.ascKey: ['key-id', 'issuer-id', 'p8', 'key-kind'],
  CredentialKind.appleId: ['apple-id', 'password-stdin'],
  CredentialKind.playSa: ['service-account'],
  CredentialKind.firebaseSa: ['service-account'],
  CredentialKind.keystore: [
    'keystore',
    'key-alias',
    'store-password-stdin',
    'key-password-stdin',
  ],
  CredentialKind.shorebird: ['token-stdin'],
  CredentialKind.slack: ['webhook-url-stdin'],
};

/// The options each kind cannot do without; its secrets aside.
const _requiredOptions = <CredentialKind, List<String>>{
  CredentialKind.ascKey: ['key-id', 'issuer-id', 'p8'],
  CredentialKind.appleId: ['apple-id'],
  CredentialKind.playSa: ['service-account'],
  CredentialKind.firebaseSa: ['service-account'],
  CredentialKind.keystore: ['keystore', 'key-alias'],
  CredentialKind.shorebird: [],
  CredentialKind.slack: [],
};

const _stdinOptions = [
  'password-stdin',
  'store-password-stdin',
  'key-password-stdin',
  'token-stdin',
  'webhook-url-stdin',
];

const _secretsFooter = r'''
A secret is never an argument. At a terminal it is asked for without being
shown; otherwise pipe it in with its --*-stdin option (one per command, since
standard input is read once), for example:
  printf %s "$SHOREBIRD_TOKEN" | xp credentials add --kind shorebird --name "Shorebird" --token-stdin''';

/// The options of every kind, for `add` and `replace`.
void _addMaterialOptions(ArgParser parser) {
  void stdinFlag(String name, String help) =>
      parser.addFlag(name, negatable: false, help: help);
  parser
    ..addSeparator('asc_key (App Store Connect API key):')
    ..addOption('key-id', help: 'The key id.', valueHelp: 'id')
    ..addOption('issuer-id', help: 'The issuer id.', valueHelp: 'uuid')
    ..addOption('p8', help: 'The .p8 file of the key.', valueHelp: 'path')
    ..addOption(
      'key-kind',
      help: 'A team key or an individual key (default: team).',
      allowed: ['team', 'individual'],
    )
    ..addSeparator('apple_id (Apple ID with an app-specific password):')
    ..addOption('apple-id', help: 'The Apple ID.', valueHelp: 'email');
  stdinFlag(
    'password-stdin',
    'Read the app-specific password from standard input.',
  );
  parser
    ..addSeparator('play_sa, firebase_sa (service account):')
    ..addOption(
      'service-account',
      help: 'The JSON key file of the service account.',
      valueHelp: 'path',
    )
    ..addSeparator('keystore (Android keystore):')
    ..addOption(
      'keystore',
      help: 'The keystore file (.jks or .keystore).',
      valueHelp: 'path',
    )
    ..addOption('key-alias', help: 'The alias of the key.', valueHelp: 'alias');
  stdinFlag(
    'store-password-stdin',
    'Read the keystore password from standard input.',
  );
  stdinFlag(
    'key-password-stdin',
    'Read the key password from standard input. Without it the key password '
        'is asked for at a terminal (empty: the keystore password).',
  );
  parser.addSeparator('shorebird (Shorebird API key):');
  stdinFlag('token-stdin', 'Read the API key from standard input.');
  parser.addSeparator('slack (Slack incoming webhook):');
  stdinFlag('webhook-url-stdin', 'Read the webhook URL from standard input.');
}

/// The secret fields of [kind] from the options of [command], the files they
/// name, the terminal and standard input.
///
/// Every option is checked before anything is read or asked, and the
/// questions come before standard input is read.
Future<Map<String, dynamic>> _material(
  XpCommand command,
  CredentialKind kind,
) async {
  final args = command.argResults!;
  final piped = [
    for (final option in _stdinOptions)
      if (args.flag(option)) option,
  ];
  if (piped.length > 1) {
    command.usageException(
      'Give only one of ${piped.map((o) => '--$o').join(', ')}: standard '
      'input can be read once.',
    );
  }
  final mine = _kindOptions[kind]!;
  for (final option in _kindOptions.values.expand((options) => options)) {
    if (args.wasParsed(option) && !mine.contains(option)) {
      command.usageException('--$option is not for --kind ${kind.wire}.');
    }
  }
  String required(String option) =>
      args.option(option) ??
      command.usageException('Missing --$option (for --kind ${kind.wire}).');

  _requiredOptions[kind]!.forEach(required);
  final secrets = _secrets[kind] ?? const <_Secret>[];
  final prompt = command.context.secretPrompt;
  final interactive = prompt.interactive;
  for (final secret in secrets) {
    if (!secret.optional && !args.flag(secret.stdinOption) && !interactive) {
      command.usageException(
        'No terminal to ask for the ${secret.label.toLowerCase()}: pipe it '
        'in with --${secret.stdinOption}.',
      );
    }
  }

  final material = <String, dynamic>{
    ...switch (kind) {
      CredentialKind.ascKey => {
        'keyId': required('key-id'),
        'issuerId': required('issuer-id'),
        'privateKey': _readText(required('p8')),
        'keyKind': ?args.option('key-kind'),
      },
      CredentialKind.appleId => {'appleId': required('apple-id')},
      CredentialKind.playSa || CredentialKind.firebaseSa => {
        'serviceAccount': _readText(required('service-account')),
      },
      CredentialKind.keystore => {
        'keystore': base64Encode(_readBytes(required('keystore'))),
        'keyAlias': required('key-alias'),
      },
      _ => const <String, String>{},
    },
  };

  for (final secret in secrets) {
    if (args.flag(secret.stdinOption) || !interactive) continue;
    final answer = prompt.ask(secret.label);
    if (answer.isNotEmpty) {
      material[secret.field] = answer;
    } else if (!secret.optional) {
      command.usageException('The ${secret.label.toLowerCase()} is empty.');
    }
  }
  for (final secret in secrets) {
    if (!args.flag(secret.stdinOption)) continue;
    final read = await utf8.decoder.bind(command.context.stdin).join();
    final value = read.replaceFirst(RegExp(r'[\r\n]+$'), '');
    if (value.isEmpty) {
      command.usageException(
        'Standard input had no ${secret.label.toLowerCase()}.',
      );
    }
    material[secret.field] = value;
  }
  return material;
}

String _readText(String path) => _read(path, File(path).readAsStringSync);

List<int> _readBytes(String path) => _read(path, File(path).readAsBytesSync);

T _read<T>(String path, T Function() read) {
  try {
    return read();
  } on FileSystemException catch (error) {
    throw ReferenceException(
      'Cannot read "$path": ${error.osError?.message ?? error.message}.',
      notFound: true,
    );
  }
}
