import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/dispatch/plan_context.dart';
import 'package:xp_engine/src/projects/project_record.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_registry.dart';
import 'package:xp_engine/src/stores/apple/app_store_profiles.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/step_catalog.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';

/// How a step type is planned: the keys it takes under `with`, the input it
/// gets, and what a runner needs to run it.
class StepPlanSpec {
  /// Creates a spec.
  new(
    this.kind,
    List<StepKey> keys,
    this.input, {
    this.needs = const [],
    this.capabilities,
    this.anyOf,
  }) : keys = {for (final key in keys) key.name: key};

  /// The step type.
  final String kind;

  /// The keys of `with`, by name.
  final Map<String, StepKey> keys;

  /// The stored input of the step, in the JSON its `decodeInput` reads.
  final Future<Map<String, dynamic>> Function(StepPlanning planning) input;

  /// What a runner needs to run the step, as the schema shows it: any one
  /// of these sets will do. Empty when the engine runs it.
  final List<Set<Capability>> needs;

  /// The capabilities a step needs, when that depends on the step; else the
  /// one set of [needs], when it has one.
  final Set<Capability> Function(StepPlanning planning)? capabilities;

  /// What else the step needs where any of several capabilities will do,
  /// the first preferred: `[ios-sign, ios-linux]` for an iOS build that a Mac
  /// or a Linux runner can make (ADR 0014).
  final List<List<Capability>> Function(StepPlanning planning)? anyOf;
}

/// What a step type is for people: its title, what it does, and the group
/// an editor lists it in.
typedef StepAbout = ({String title, String description, String group});

/// The step types a workflow can use and how each is planned when a workflow
/// is dispatched.
///
/// A step of a workflow names a type and a few `with` values. The engine fills
/// in the rest from what the dispatch decided: the worktree, the commit, the
/// version and build number, the flavor and its ids, the Flutter pin, the
/// secrets of the credentials the flavor has. The result is the stored input
/// of a step of `JobRunner`, checked by the step type itself.
class StepPlanners implements StepCatalog {
  /// Creates the planners over `registry`, whose steps check the inputs.
  ///
  /// With [linuxIosBuilds], `build.ios` and `ios.stripAndReexport` need any
  /// of `ios-sign` and `ios-linux`, and the dispatcher narrows a job Linux
  /// cannot build to `ios-sign` (ADR 0014). `xpd` turns it on: `build.ios`
  /// has a Linux backend. Off, iOS builds need a Mac, as before.
  new(this._registry, {this.linuxIosBuilds = false}) {
    for (final spec in _specs) {
      _bySpec[spec.kind] = spec;
    }
  }

  final StepRegistry _registry;
  final _bySpec = <String, StepPlanSpec>{};

  /// Whether iOS builds may run on a Linux runner.
  final bool linuxIosBuilds;

  @override
  Iterable<String> get kinds => _bySpec.keys.toList()..sort();

  @override
  Set<String>? withKeys(String kind) => _bySpec[kind]?.keys.keys.toSet();

  @override
  Map<String, StepKey>? keysOf(String kind) => _bySpec[kind]?.keys;

  @override
  StepType? describe(String kind) {
    final spec = _bySpec[kind];
    if (spec == null) return null;
    final about = stepAbout[kind]!;
    return StepType(
      kind: kind,
      withKeys: spec.keys.keys.toList()..sort(),
      title: about.title,
      description: about.description,
      group: about.group,
      capabilities: [
        for (final set in spec.needs)
          [for (final capability in set) capability.wire],
      ],
      keys: [for (final key in spec.keys.values) key.toWire()],
    );
  }

  /// What the step needs of a runner: one need per capability it needs, then
  /// its any-of needs.
  List<CapabilityNeed> needsOf(StepPlanning planning) {
    final spec = _bySpec[planning.kind];
    if (spec == null) return const [];
    final all =
        spec.capabilities?.call(planning) ??
        (spec.needs.length == 1 ? spec.needs.single : const <Capability>{});
    final anyOf = spec.anyOf?.call(planning) ?? const <List<Capability>>[];
    return [
      for (final capability in all) CapabilityNeed([capability]),
      for (final capabilities in anyOf) CapabilityNeed(capabilities),
    ];
  }

  /// The plan of the step [planning].
  ///
  /// Throws a [DispatchException] if the step cannot be planned: a value it
  /// needs is missing, a credential is not saved, or the step type refuses
  /// the input.
  Future<StepPlan> plan(StepPlanning planning) async {
    final spec = _bySpec[planning.kind]!;
    final json = await spec.input(planning);
    return _checked(planning.kind, json, planning);
  }

  /// The plan of a gate in front of a step.
  StepPlan gate({
    required GateAction action,
    required String projectId,
    required String sha,
    String? version,
  }) => _check('gate', {
    'action': action.wire,
    'projectId': projectId,
    'sha': sha,
    'version': ?version,
  });

  StepPlan _checked(String kind, Map<String, dynamic> json, StepPlanning at) {
    try {
      return _check(kind, json);
    } on FormatException catch (error) {
      at.fail(error.message);
    }
  }

  StepPlan _check(String kind, Map<String, dynamic> json) {
    final step = _registry[kind];
    if (step == null) {
      throw DispatchException('This engine cannot run steps of type "$kind".');
    }
    final input = step.decodeInput(json);
    return StepPlan(
      kind: kind,
      input: step.encodeInput(input),
      sideEffect: step.sideEffectOf(input),
    );
  }

  late final List<StepPlanSpec> _specs = [
    StepPlanSpec(
      'command',
      const [
        StepKey.needed(
          'executable',
          description: 'The program to run, such as dart or ./tool/x.sh.',
        ),
        StepKey(
          'arguments',
          value: StepValue.texts,
          description: 'Its arguments, one item each.',
        ),
        StepKey(
          'workingDirectory',
          description: 'A folder inside the app to run it in.',
        ),
        StepKey(
          'environment',
          value: StepValue.textMap,
          description: 'Environment variables to set.',
        ),
        StepKey(
          'passThroughEnvironment',
          value: StepValue.texts,
          description: 'Environment variables of the engine to pass on.',
        ),
        StepKey(
          'secretEnvironment',
          value: StepValue.textMap,
          description: 'Variables set to stored secrets, by variable.',
        ),
        StepKey(
          'secretFiles',
          value: StepValue.textMap,
          description: 'Variables set to the path of a stored secret file.',
        ),
        StepKey(
          'sideEffect',
          value: StepValue.flag,
          description: 'Whether it changes something outside the job.',
          defaultValue: false,
        ),
      ],
      (p) async {
        final directory = p.text('workingDirectory');
        return {
          'executable': p.requireText('executable'),
          'arguments': p.list('arguments'),
          'workingDirectory': _inJob(p, directory),
          'environment': p.strings('environment'),
          'passThroughEnvironment': p.list('passThroughEnvironment'),
          'secretEnvironment': p.strings('secretEnvironment'),
          'secretFiles': p.strings('secretFiles'),
          'sideEffect': p.flag('sideEffect'),
        };
      },
    ),
    StepPlanSpec(
      'git.checkout',
      const [
        StepKey(
          'commitFrom',
          description: 'A job of an earlier stage whose commit to start from.',
        ),
      ],
      (p) async {
        final source = p.text('commitFrom');
        return {
          'worktree': p.job.worktree.toJson(),
          if (source != null)
            'commitFromJob':
                p.job.commitSources[source] ??
                p.fail('The job "$source" has no job to start from here.'),
        };
      },
    ),
    StepPlanSpec(
      'guard',
      [
        StepKey.choice(
          'checks',
          [for (final check in GuardCheckName.values) check.name],
          value: StepValue.texts,
          description: 'The checks to run before going on.',
        ),
        StepKey.choice(
          'credentialKinds',
          [for (final kind in CredentialKind.values) kind.wire],
          value: StepValue.texts,
          description: 'The credentials the flavor must have, checked.',
        ),
      ],
      (p) async {
        final flavor = p.job.flavor;
        return {
          'checks': p.list('checks'),
          'worktree': p.job.worktree.toJson(),
          if (p.job.run.releaseVersion != null)
            'releaseVersion': '${p.job.run.releaseVersion}',
          'iosBundleId': ?flavor?.iosBundleId,
          'androidAppId': ?flavor?.androidAppId,
          'shorebirdAppId': ?_shorebirdAppId(p),
          'storeCountry': p.job.run.app.storeCountry,
          'flavorId': ?p.job.credentialFlavor?.id,
          'credentialKinds': p.list('credentialKinds'),
        };
      },
    ),
    // A workflow with this step always has a version: the dispatch allocates
    // it for exactly such workflows.
    StepPlanSpec(
      'version.bump',
      const [],
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'version': '${p.job.run.version}',
      },
    ),
    StepPlanSpec(
      'build.android',
      const [
        StepKey.choice(
          'artifact',
          ['apk', 'aab'],
          description: 'An APK to install, or an App Bundle for Google Play.',
          defaultValue: 'apk',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'obfuscate',
          value: StepValue.flag,
          description: 'Obfuscate the Dart code and keep its symbols.',
          defaultValue: false,
        ),
        StepKey(
          'keystore',
          value: StepValue.flag,
          description: 'Sign with the keystore of the flavor, when it has one.',
          defaultValue: true,
        ),
      ],
      (p) async => {
        ..._settings(p, signing: p.flag('keystore', otherwise: true)),
        'artifact': p.text('artifact') ?? 'apk',
      },
      needs: const [
        {Capability.android, Capability.flutter},
      ],
    ),
    StepPlanSpec(
      'build.ios',
      const [
        StepKey.needed(
          'exportOptionsPlist',
          description: 'The export options plist, in the app.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'obfuscate',
          value: StepValue.flag,
          description: 'Obfuscate the Dart code and keep its symbols.',
          defaultValue: false,
        ),
      ],
      (p) async => {
        ..._settings(p),
        'exportOptionsPlist': p.requireText('exportOptionsPlist'),
        'linuxSigning': ?_linuxSigning(p),
      },
      needs: linuxIosBuilds
          ? const [
              {Capability.iosSign, Capability.flutter},
              {Capability.iosLinux, Capability.flutter},
            ]
          : const [
              {Capability.iosSign, Capability.flutter},
            ],
      capabilities: (_) => linuxIosBuilds
          ? const {Capability.flutter}
          : const {Capability.iosSign, Capability.flutter},
      anyOf: (_) => _iosBuild,
    ),
    StepPlanSpec(
      'build.verifyCompiledConfig',
      const [
        StepKey(
          'artifactName',
          description:
              'The artifact to look in; the one of the job by default.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'keys',
          value: StepValue.texts,
          description:
              'The keys of the file whose values must be in the build.',
        ),
        StepKey(
          'needles',
          value: StepValue.texts,
          description: 'Other text that must be in the build.',
        ),
      ],
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'artifactName': p.text('artifactName') ?? _artifactName(p),
        'dartDefineFile': ?p.text('dartDefineFile'),
        'keys': p.list('keys'),
        'needles': p.list('needles'),
      },
    ),
    StepPlanSpec(
      'ios.stripAndReexport',
      const [
        StepKey(
          'frameworks',
          value: StepValue.texts,
          description: 'The frameworks to strip from the archive.',
        ),
        StepKey.needed(
          'exportOptionsPlist',
          description: 'The export options plist, in the app.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
      ],
      (p) async => {
        ..._settings(p),
        'exportOptionsPlist': p.requireText('exportOptionsPlist'),
        'frameworks': p.list('frameworks'),
      },
      needs: linuxIosBuilds
          ? const [
              {Capability.iosSign},
              {Capability.iosLinux},
            ]
          : const [
              {Capability.iosSign},
            ],
      capabilities: (_) =>
          linuxIosBuilds ? const {} : const {Capability.iosSign},
      anyOf: (_) => _iosBuild,
    ),
    StepPlanSpec(
      'shorebird.release',
      const [
        StepKey.choice(
          'platform',
          platformNames,
          description: 'The platform; the one of the job by default.',
        ),
        StepKey.choice(
          'artifact',
          ['apk', 'aab'],
          description: 'For Android, an APK or an App Bundle.',
          defaultValue: 'aab',
        ),
        StepKey(
          'exportOptionsPlist',
          description: 'For iOS, the export options plist, in the app.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'obfuscate',
          value: StepValue.flag,
          description: 'Obfuscate the Dart code and keep its symbols.',
          defaultValue: false,
        ),
        StepKey(
          'keystore',
          value: StepValue.flag,
          description: 'Sign with the keystore of the flavor, when it has one.',
          defaultValue: true,
        ),
        StepKey(
          'shorebirdAppId',
          description: 'The Shorebird app; the one of the flavor by default.',
        ),
      ],
      (p) async {
        final platform = _platformOf(p);
        return {
          ..._settings(
            p,
            signing:
                platform == 'android' && p.flag('keystore', otherwise: true),
          ),
          'platform': platform,
          'shorebirdAppId':
              p.text('shorebirdAppId') ??
              _shorebirdAppId(p) ??
              p.fail(
                'The flavor has no Shorebird app id; give "shorebirdAppId".',
              ),
          'artifact': p.text('artifact') ?? 'aab',
          'exportOptionsPlist': ?p.text('exportOptionsPlist'),
          'tokenSecret': ?_secretOf(p, CredentialKind.shorebird),
        };
      },
      needs: _shorebirdNeeds,
      capabilities: (p) => _shorebirdCapabilities(_platformOf(p)),
    ),
    StepPlanSpec(
      'shorebird.patch',
      const [
        StepKey.choice(
          'platform',
          platformNames,
          description: 'The platform; the one of the job by default.',
        ),
        StepKey(
          'exportOptionsPlist',
          description: 'For iOS, the export options plist, in the app.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'obfuscate',
          value: StepValue.flag,
          description: 'Obfuscate the Dart code and keep its symbols.',
          defaultValue: false,
        ),
        StepKey(
          'allowNativeDiffs',
          value: StepValue.flag,
          description: 'Patch even when native code changed since the release.',
          defaultValue: false,
        ),
        StepKey(
          'shorebirdAppId',
          description: 'The Shorebird app; the one of the flavor by default.',
        ),
      ],
      (p) async {
        final platform = _platformOf(p);
        return {
          ..._settings(p),
          'platform': platform,
          'shorebirdAppId':
              p.text('shorebirdAppId') ??
              _shorebirdAppId(p) ??
              p.fail(
                'The flavor has no Shorebird app id; give "shorebirdAppId".',
              ),
          'exportOptionsPlist': ?p.text('exportOptionsPlist'),
          'allowNativeDiffs': p.flag('allowNativeDiffs'),
          'tokenSecret': ?_secretOf(p, CredentialKind.shorebird),
        };
      },
      needs: _shorebirdNeeds,
      capabilities: (p) => _shorebirdCapabilities(_platformOf(p)),
    ),
    StepPlanSpec(
      'symbols.archive',
      const [
        StepKey(
          'android',
          value: StepValue.flag,
          description:
              'Keep the Android symbols; in an Android job by default.',
        ),
        StepKey(
          'ios',
          value: StepValue.flag,
          description: 'Keep the iOS symbols; in an iOS job by default.',
        ),
        StepKey(
          'debugInfoDirectory',
          description: 'Where the build wrote the Dart symbols.',
        ),
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
        StepKey(
          'obfuscate',
          value: StepValue.flag,
          description: 'Whether the build was obfuscated.',
          defaultValue: false,
        ),
      ],
      (p) async => {
        ..._settings(p),
        'android': p.flag('android', otherwise: p.job.platform == 'android'),
        'ios': p.flag('ios', otherwise: p.job.platform == 'ios'),
        'debugInfoDirectory': ?p.text('debugInfoDirectory'),
      },
    ),
    StepPlanSpec(
      'record.manifest',
      const [
        StepKey(
          'dartDefineFile',
          description:
              'A JSON or .env file of --dart-define values, in the app.',
        ),
      ],
      (p) async {
        final version = p.job.run.stepVersion;
        if (version?.build == null) return _needsBuild(p);
        return {
          'worktree': p.job.worktree.toJson(),
          'version': '$version',
          'flavors': [?p.job.flavor?.name],
          'dartDefineFile': ?p.text('dartDefineFile'),
        };
      },
    ),
    StepPlanSpec(
      'test',
      const [
        StepKey(
          'paths',
          value: StepValue.texts,
          description: 'The test files or folders; all tests by default.',
        ),
        StepKey(
          'tags',
          value: StepValue.texts,
          description: 'Run only the tests with these tags.',
        ),
      ],
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'branch': p.job.run.ref,
        'baseBranch': p.job.run.project.defaultBaseBranch,
        'flutterVersion': ?p.job.run.app.flutterVersion,
        'paths': p.list('paths'),
        'tags': p.list('tags'),
      },
      needs: const [
        {Capability.flutter},
      ],
    ),
    StepPlanSpec(
      'analyze',
      const [
        StepKey.choice(
          'failOn',
          ['error', 'warning', 'info'],
          description: 'The least severe issue that fails the step.',
          defaultValue: 'error',
        ),
      ],
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'flutterVersion': ?p.job.run.app.flutterVersion,
        'failOn': ?p.text('failOn'),
      },
      needs: const [
        {Capability.flutter},
      ],
    ),
    StepPlanSpec(
      'upload.firebase',
      const [
        StepKey(
          'artifactName',
          description: 'The file to upload; the APK of the job by default.',
        ),
        StepKey(
          'artifactsFrom',
          description: 'A build job of an earlier stage to take the file from.',
        ),
        StepKey.needed(
          'appId',
          description: 'The Firebase app id, such as 1:123:android:abc.',
        ),
        StepKey(
          'testerEmails',
          value: StepValue.texts,
          description: 'Testers to invite, by email.',
        ),
        StepKey(
          'groupAliases',
          value: StepValue.texts,
          description: 'Tester groups to invite, by alias.',
        ),
        StepKey('releaseNotes', description: 'What the testers see.'),
      ],
      (p) async {
        final version = _version(p);
        return {
          'artifactName': p.text('artifactName') ?? _artifactName(p, 'apk'),
          'appId': p.requireText('appId'),
          'version': '$version',
          'serviceAccountSecret': _requiredSecret(p, CredentialKind.firebaseSa),
          'testerEmails': p.list('testerEmails'),
          'groupAliases': p.list('groupAliases'),
          'releaseNotes': ?_blankToNull(p.text('releaseNotes')),
          'artifactJob': ?_artifactJob(p),
        };
      },
    ),
    StepPlanSpec(
      'upload.play',
      const [
        StepKey(
          'artifactName',
          description:
              'The file to upload; the App Bundle of the job by default.',
        ),
        StepKey(
          'artifactsFrom',
          description: 'A build job of an earlier stage to take the file from.',
        ),
        StepKey(
          'packageName',
          description: 'The application id; the one of the flavor by default.',
        ),
        StepKey(
          'track',
          description: 'The track: internal, alpha, beta, production or yours.',
          defaultValue: 'internal',
        ),
        StepKey.choice(
          'status',
          ['completed', 'inProgress', 'draft'],
          description: 'Release now, roll out to a fraction, or keep a draft.',
          defaultValue: 'completed',
        ),
        StepKey(
          'userFraction',
          value: StepValue.number,
          description:
              'For a roll-out, the fraction of users, above 0, below 1.',
        ),
        StepKey('releaseName', description: 'The name of the release.'),
        StepKey(
          'releaseNotes',
          value: StepValue.textMap,
          description: 'What is new, by language, such as en-US.',
        ),
      ],
      (p) async {
        final version = _version(p);
        return {
          'artifactName': p.text('artifactName') ?? _artifactName(p, 'aab'),
          'packageName':
              p.text('packageName') ??
              p.job.flavor?.androidAppId ??
              p.fail('The flavor has no Android application id.'),
          'version': '$version',
          'serviceAccountSecret': _requiredSecret(p, CredentialKind.playSa),
          'track': ?p.text('track'),
          'status': ?p.text('status'),
          'userFraction': ?p.number('userFraction'),
          'releaseName': ?p.text('releaseName'),
          'releaseNotes': p.strings('releaseNotes'),
          'artifactJob': ?_artifactJob(p),
        };
      },
    ),
    StepPlanSpec(
      'upload.appStore',
      const [
        StepKey(
          'artifactName',
          description: 'The file to upload; the IPA of the job by default.',
        ),
        StepKey(
          'artifactsFrom',
          description: 'A build job of an earlier stage to take the file from.',
        ),
        StepKey(
          'bundleId',
          description: 'The bundle id; the one of the flavor by default.',
        ),
        StepKey.needed(
          'appleAppId',
          description: 'The App Store Connect app id, a number.',
        ),
      ],
      (p) async {
        final version = _version(p);
        final key = p.job.credential(CredentialKind.ascKey);
        final appleId = p.job.credential(CredentialKind.appleId);
        if (key == null && appleId == null) {
          final flavor = p.job.flavor?.name ?? 'default';
          p.fail(
            'The flavor has no App Store Connect key or Apple ID assigned. '
            'Assign one to the flavor first.',
            hint:
                'Add an App Store Connect API key or an Apple ID credential '
                'and assign it to $flavor, then dispatch again.',
            details: {
              'reason': ErrorReason.credentialUnassigned,
              'kinds': [
                CredentialKind.ascKey.wire,
                CredentialKind.appleId.wire,
              ],
              'flavor': flavor,
            },
          );
        }
        return {
          'artifactName': p.text('artifactName') ?? _artifactName(p, 'ipa'),
          'bundleId':
              p.text('bundleId') ??
              p.job.flavor?.iosBundleId ??
              p.fail('The flavor has no iOS bundle id.'),
          'appleAppId': p.requireText('appleAppId'),
          'version': '$version',
          'auth': key != null
              ? {'type': 'apiKey', 'keySecret': key.secretKey}
              : {
                  'type': 'appleId',
                  'appleId':
                      appleId!.account ??
                      p.fail('The Apple ID credential has no Apple ID.'),
                  'passwordSecret': appleId.secretKey,
                },
          'artifactJob': ?_artifactJob(p),
        };
      },
      needs: const [
        {Capability.iosSign},
      ],
      // An API key uploads through the REST API on any engine; altool, for an
      // Apple ID, needs a Mac (ADR 0014).
      capabilities: (p) => p.job.credential(CredentialKind.ascKey) != null
          ? const {}
          : const {Capability.iosSign},
    ),
    StepPlanSpec('git.releaseBranch', const [], (p) async {
      final version = p.job.run.version;
      if (version == null) {
        return p.fail('There is no release version: this run bumps none.');
      }
      return {
        'worktree': p.job.worktree.toJson(),
        'version': '${version.name}',
      };
    }),
    StepPlanSpec('git.tag', const [], (p) async {
      final run = p.job.run;
      final release = run.releaseVersion;
      final version = run.stepVersion;
      if (version?.build == null) return _needsBuild(p);
      final scope = p.job.worktree.scope;
      final patch = run.patch;
      final name = release != null && patch != null
          ? run.model.patchTagName(
              release.name,
              release.build!,
              patch,
              scope: scope,
            )
          : run.model.tagName(version!.name, version.build!, scope: scope);
      return {
        'worktree': p.job.worktree.toJson(),
        'name': name,
        'message': patch != null
            ? 'Patch $patch of $release'
            : 'Release $version',
      };
    }),
    StepPlanSpec(
      'git.push',
      const [
        StepKey(
          'branch',
          value: StepValue.flag,
          description:
              'Push the release branch; when the run bumps by default.',
        ),
        StepKey(
          'tag',
          value: StepValue.flag,
          description: 'Push the tag.',
          defaultValue: true,
        ),
      ],
      (p) async {
        final run = p.job.run;
        final release = run.releaseVersion;
        final version = run.stepVersion;
        if (version?.build == null) return _needsBuild(p);
        final scope = p.job.worktree.scope;
        final patch = run.patch;
        final tag = release != null && patch != null
            ? run.model.patchTagName(
                release.name,
                release.build!,
                patch,
                scope: scope,
              )
            : run.model.tagName(version!.name, version.build!, scope: scope);
        final withBranch = p.flag('branch', otherwise: run.version != null);
        return {
          'worktree': p.job.worktree.toJson(),
          if (withBranch)
            'branch': run.model.branchName(version!.name, scope: scope),
          if (p.flag('tag', otherwise: true)) 'tag': tag,
        };
      },
    ),
    StepPlanSpec(
      'github.createPr',
      const [
        StepKey('title', description: 'The title; "Release x.y.z" by default.'),
        StepKey('body', description: 'The description of the pull request.'),
      ],
      (p) async {
        final run = p.job.run;
        final version = run.version;
        if (version == null) {
          return p.fail('There is no release version: this run bumps none.');
        }
        final flavor = p.job.flavor;
        return {
          'githubRepoId': _githubRepoIdOf(run.project, p.fail),
          'head': run.model.branchName(
            version.name,
            scope: p.job.worktree.scope,
          ),
          'base': run.project.defaultBaseBranch,
          'title':
              p.text('title') ??
              'Release ${version.name}${_flavorSuffix(flavor)}',
          'body':
              p.text('body') ??
              'The release branch of ${version.name}, opened by XPath. Merge '
                  'it once every store has the release live.',
        };
      },
    ),
    StepPlanSpec(
      'github.mergePr',
      const [],
      (p) async => {
        'releaseId':
            p.job.run.release ??
            p.fail(
              'There is no release to merge: dispatch this workflow with '
              '"release", or with POST /releases/{id}/merge.',
            ),
        'githubRepoId': _githubRepoIdOf(p.job.run.project, p.fail),
      },
    ),
  ];

  // --------------------------------------------------------------- helpers

  /// The GitHub id of [project] for a GitHub step. The dispatcher refuses
  /// these steps on any other project (ADR 0015); [fail] says so if one gets
  /// here all the same.
  static int _githubRepoIdOf(
    ProjectRecord project,
    Never Function(String message) fail,
  ) =>
      project.githubRepoId ??
      fail('${project.fullName} is not on GitHub, so it has no pull request.');

  static String _flavorSuffix(FlavorProfile? flavor) =>
      flavor == null || flavor.implicit ? '' : ' (${flavor.name})';

  static Map<String, dynamic> _needsBuild(StepPlanning p) => p.fail(
    'The app has no build number, and this run allocates none: add a '
    '"version.bump" step before it.',
  );

  static AppVersion _version(StepPlanning p) {
    final version = p.job.run.stepVersion;
    if (version?.build == null) {
      _needsBuild(p);
    }
    return version!;
  }

  static String? _inJob(StepPlanning p, String? directory) {
    final worktree = p.job.worktree;
    final app = worktree.appPath == '.'
        ? worktree.path
        : '${worktree.path}/${worktree.appPath}';
    if (directory == null) return app;
    if (directory.startsWith('/') || directory.split('/').contains('..')) {
      p.fail('"workingDirectory" must be a folder inside the app.');
    }
    return '$app/$directory';
  }

  static String _platformOf(StepPlanning p) {
    final platform = p.text('platform') ?? p.job.platform;
    if (platform != 'android' && platform != 'ios') {
      p.fail(
        '"platform" must be android or ios; the job has none, so give it '
        'under "with".',
      );
    }
    return platform!;
  }

  static const List<Set<Capability>> _shorebirdNeeds = [
    {Capability.flutter, Capability.android},
    {Capability.flutter, Capability.iosSign},
  ];

  static Set<Capability> _shorebirdCapabilities(String platform) =>
      _shorebirdNeeds[platform == 'ios' ? 1 : 0];

  /// Where an iOS build can be made: a Mac, preferred, or a Linux runner,
  /// once [linuxIosBuilds] allows it.
  List<List<Capability>> get _iosBuild => linuxIosBuilds
      ? const [
          [Capability.iosSign, Capability.iosLinux],
        ]
      : const [];

  static String? _shorebirdAppId(StepPlanning p) {
    final flavor = p.job.flavor;
    final app = p.job.run.app;
    return flavor?.shorebirdAppId ??
        app.shorebird?.flavorAppIds[flavor?.name] ??
        app.shorebird?.appId;
  }

  /// The job whose artifacts an upload step takes its file from
  /// (`artifactsFrom`), as planned: a build job of an earlier stage whose
  /// matrix cell agrees with this one (ADR 0010). `null` for the job itself.
  static String? _artifactJob(StepPlanning p) {
    final source = p.text('artifactsFrom');
    if (source == null) return null;
    return p.job.commitSources[source] ??
        p.fail('The job "$source" has no job to take the artifact from here.');
  }

  static String? _secretOf(StepPlanning p, CredentialKind kind) =>
      p.job.credential(kind)?.secretKey;

  static String _requiredSecret(StepPlanning p, CredentialKind kind) {
    final flavor = p.job.flavor?.name ?? 'default';
    return _secretOf(p, kind) ??
        p.fail(
          'The flavor "$flavor" has no ${kind.wire} credential assigned. '
          'Assign one to the flavor first.',
          hint:
              'Add a ${kind.label} credential and assign it to $flavor, then '
              'dispatch again.',
          details: {
            'reason': ErrorReason.credentialUnassigned,
            'kind': kind.wire,
            'flavor': flavor,
          },
        );
  }

  /// What a Linux runner signs the iOS build with (ADR 0014): the flavor's
  /// Apple Distribution identity and the App Store profile the engine makes
  /// for it with the flavor's App Store Connect key, by the variable
  /// omarchy-apple-dev's `flutter/ship.sh` reads. `null` unless the flavor
  /// has both and a bundle id; the job then cannot sign on Linux.
  static Map<String, String>? _linuxSigning(StepPlanning p) {
    final identity = p.job.credential(CredentialKind.appleDistribution);
    final bundleId = identity?.flavor.iosBundleId;
    if (identity == null ||
        bundleId == null ||
        p.job.credential(CredentialKind.ascKey) == null) {
      return null;
    }
    return {
      linuxSigningKeyVariable: identity.secretKey,
      linuxSigningCertificateVariable: AppleDistributionMaterial.certificateKey(
        identity.secretKey,
      ),
      linuxSigningProfileVariable: AppStoreProfiles.keyFor(
        identity.secretKey,
        bundleId,
      ),
    };
  }

  static String? _blankToNull(String? text) =>
      text == null || text.trim().isEmpty ? null : text;

  /// The file name the build steps give their artifact: `dev-1.2.3+45.apk`.
  static String _artifactName(StepPlanning p, [String? extension]) {
    final version = _version(p);
    final flavor = p.job.flavor;
    final label =
        '${flavor == null || flavor.implicit ? 'app' : flavor.name}'
        '-$version';
    return '$label.${extension ?? (p.job.platform == 'ios' ? 'ipa' : 'apk')}';
  }

  /// The stored settings of a build step, the part `BuildSettings` reads.
  static Map<String, dynamic> _settings(
    StepPlanning p, {
    bool signing = false,
  }) {
    final flavor = p.job.flavor;
    final keystore = signing ? p.job.credential(CredentialKind.keystore) : null;
    final target = flavor?.entrypoint;
    return {
      'worktree': p.job.worktree.toJson(),
      'version': '${_version(p)}',
      if (flavor != null && !flavor.implicit) 'flavor': flavor.name,
      if (target != null && target != 'lib/main.dart') 'target': target,
      'flutterVersion': ?p.job.run.app.flutterVersion,
      'dartDefineFile': ?p.text('dartDefineFile'),
      'obfuscate': p.flag('obfuscate'),
      if (keystore != null)
        'secretFiles': {keystoreFileVariable: keystore.secretKey},
      if (keystore != null)
        'secretEnvironment': {
          keystoreStorePasswordVariable: KeystoreMaterial.storePasswordKey(
            keystore.secretKey,
          ),
          keystoreKeyPasswordVariable: KeystoreMaterial.keyPasswordKey(
            keystore.secretKey,
          ),
        },
    };
  }
}

/// The variable that holds the path of the keystore file for an Android
/// build, when the flavor has a `keystore` credential.
const keystoreFileVariable = 'XPATH_KEYSTORE_FILE';

/// The variable that holds the store password of the keystore.
const keystoreStorePasswordVariable = 'XPATH_KEYSTORE_STORE_PASSWORD';

/// The variable that holds the key password of the keystore.
const keystoreKeyPasswordVariable = 'XPATH_KEYSTORE_KEY_PASSWORD';

/// The variable that holds the path of the private key of the Apple
/// Distribution identity on a Linux runner (omarchy-apple-dev).
const linuxSigningKeyVariable = 'ASC_SIGNING_KEY';

/// The variable that holds the path of the identity's certificate (DER).
const linuxSigningCertificateVariable = 'ASC_SIGNING_CERT';

/// The variable that holds the path of the App Store profile the engine
/// made for the job.
const linuxSigningProfileVariable = 'ASC_PROFILE';

/// What each step type is, for people: the schema gives it to editors.
const stepAbout = <String, StepAbout>{
  'git.checkout': (
    title: 'Check out',
    description:
        'Makes the worktree of the job at the commit of the run, or at the '
        'commit an earlier job left.',
    group: 'Source',
  ),
  'version.bump': (
    title: 'Bump the version',
    description:
        'Writes the version and build number of the run to the pubspec and '
        'commits it in the job.',
    group: 'Source',
  ),
  'git.releaseBranch': (
    title: 'Make the release branch',
    description: 'Makes the release branch of the version at the commit.',
    group: 'Source',
  ),
  'git.tag': (
    title: 'Tag the release',
    description: 'Tags the commit with the version and build number.',
    group: 'Source',
  ),
  'git.push': (
    title: 'Push',
    description: 'Pushes the release branch and the tag to GitHub.',
    group: 'Source',
  ),
  'guard': (
    title: 'Check before going on',
    description:
        'Stops the job when a check fails: the version, the store, the '
        'credentials, native changes in a patch.',
    group: 'Checks',
  ),
  'analyze': (
    title: 'Analyze',
    description: 'Runs flutter analyze and fails on issues.',
    group: 'Checks',
  ),
  'test': (
    title: 'Run the tests',
    description: 'Runs flutter test and keeps the results.',
    group: 'Checks',
  ),
  'build.verifyCompiledConfig': (
    title: 'Verify the compiled config',
    description:
        'Checks that the build has the values of the dart-define file in it.',
    group: 'Checks',
  ),
  'build.android': (
    title: 'Build Android',
    description: 'Builds an APK or an App Bundle of the flavor.',
    group: 'Build',
  ),
  'build.ios': (
    title: 'Build iOS',
    description: 'Builds and signs an IPA of the flavor.',
    group: 'Build',
  ),
  'ios.stripAndReexport': (
    title: 'Strip frameworks and export again',
    description:
        'Removes frameworks from the iOS archive and exports the IPA again.',
    group: 'Build',
  ),
  'shorebird.release': (
    title: 'Shorebird release',
    description: 'Builds a release that Shorebird can patch later.',
    group: 'Build',
  ),
  'shorebird.patch': (
    title: 'Shorebird patch',
    description: 'Builds a patch of a Shorebird release and publishes it.',
    group: 'Build',
  ),
  'symbols.archive': (
    title: 'Keep the symbols',
    description:
        'Keeps the debug symbols of the build, to read crash reports later.',
    group: 'Build',
  ),
  'record.manifest': (
    title: 'Record the release',
    description: 'Records what the release was built from.',
    group: 'Build',
  ),
  'upload.firebase': (
    title: 'Upload to Firebase',
    description: 'Sends the build to testers with Firebase App Distribution.',
    group: 'Upload',
  ),
  'upload.play': (
    title: 'Upload to Google Play',
    description: 'Uploads the App Bundle to a track of Google Play.',
    group: 'Upload',
  ),
  'upload.appStore': (
    title: 'Upload to App Store Connect',
    description: 'Uploads the IPA to App Store Connect, for TestFlight.',
    group: 'Upload',
  ),
  'github.createPr': (
    title: 'Open a pull request',
    description: 'Opens a pull request from the release branch.',
    group: 'GitHub',
  ),
  'github.mergePr': (
    title: 'Merge the pull request',
    description: 'Merges the pull request of the release.',
    group: 'GitHub',
  ),
  'command': (
    title: 'Run a command',
    description: 'Runs a program in the app, with the variables you give it.',
    group: 'Other',
  ),
};
