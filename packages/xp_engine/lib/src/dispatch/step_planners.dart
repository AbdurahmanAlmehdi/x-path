import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/dispatch/plan_context.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_registry.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/step_catalog.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';

/// How a step type is planned: the keys it takes under `with`, the input it
/// gets, and what a runner needs to run it.
class StepPlanSpec {
  /// Creates a spec.
  const new(this.kind, this.withKeys, this.input, {this.capabilities});

  /// The step type.
  final String kind;

  /// The keys of `with`.
  final Set<String> withKeys;

  /// The stored input of the step, in the JSON its `decodeInput` reads.
  final Future<Map<String, dynamic>> Function(StepPlanning planning) input;

  /// The capabilities the step needs, when it needs any.
  final Set<Capability> Function(StepPlanning planning)? capabilities;
}

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
  new(this._registry) {
    for (final spec in _specs) {
      _bySpec[spec.kind] = spec;
    }
  }

  final StepRegistry _registry;
  final _bySpec = <String, StepPlanSpec>{};

  @override
  Iterable<String> get kinds => _bySpec.keys.toList()..sort();

  @override
  Set<String>? withKeys(String kind) => _bySpec[kind]?.withKeys;

  /// The capabilities the step needs.
  Set<Capability> capabilitiesOf(StepPlanning planning) =>
      _bySpec[planning.kind]?.capabilities?.call(planning) ?? const {};

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
      const {
        'executable',
        'arguments',
        'workingDirectory',
        'environment',
        'passThroughEnvironment',
        'secretEnvironment',
        'secretFiles',
        'sideEffect',
      },
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
    StepPlanSpec('git.checkout', const {'commitFrom'}, (p) async {
      final source = p.text('commitFrom');
      return {
        'worktree': p.job.worktree.toJson(),
        if (source != null)
          'commitFromJob':
              p.job.commitSources[source] ??
              p.fail('The job "$source" has no job to start from here.'),
      };
    }),
    StepPlanSpec('guard', const {'checks', 'credentialKinds'}, (p) async {
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
    }),
    // A workflow with this step always has a version: the dispatch allocates
    // it for exactly such workflows.
    StepPlanSpec(
      'version.bump',
      const {},
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'version': '${p.job.run.version}',
      },
    ),
    StepPlanSpec(
      'build.android',
      const {'artifact', 'dartDefineFile', 'obfuscate', 'keystore'},
      (p) async => {
        ..._settings(p, signing: p.flag('keystore', otherwise: true)),
        'artifact': p.text('artifact') ?? 'apk',
      },
      capabilities: (_) => const {Capability.android, Capability.flutter},
    ),
    StepPlanSpec(
      'build.ios',
      const {'exportOptionsPlist', 'dartDefineFile', 'obfuscate'},
      (p) async => {
        ..._settings(p),
        'exportOptionsPlist': p.requireText('exportOptionsPlist'),
      },
      capabilities: (_) => const {Capability.iosSign, Capability.flutter},
    ),
    StepPlanSpec(
      'build.verifyCompiledConfig',
      const {'artifactName', 'dartDefineFile', 'keys', 'needles'},
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
      const {'frameworks', 'exportOptionsPlist', 'dartDefineFile'},
      (p) async => {
        ..._settings(p),
        'exportOptionsPlist': p.requireText('exportOptionsPlist'),
        'frameworks': p.list('frameworks'),
      },
      capabilities: (_) => const {Capability.iosSign},
    ),
    StepPlanSpec(
      'shorebird.release',
      const {
        'platform',
        'artifact',
        'exportOptionsPlist',
        'dartDefineFile',
        'obfuscate',
        'keystore',
        'shorebirdAppId',
      },
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
      capabilities: (p) => _shorebirdCapabilities(_platformOf(p)),
    ),
    StepPlanSpec(
      'shorebird.patch',
      const {
        'platform',
        'exportOptionsPlist',
        'dartDefineFile',
        'obfuscate',
        'allowNativeDiffs',
        'shorebirdAppId',
      },
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
      capabilities: (p) => _shorebirdCapabilities(_platformOf(p)),
    ),
    StepPlanSpec(
      'symbols.archive',
      const {
        'android',
        'ios',
        'debugInfoDirectory',
        'dartDefineFile',
        'obfuscate',
      },
      (p) async => {
        ..._settings(p),
        'android': p.flag('android', otherwise: p.job.platform == 'android'),
        'ios': p.flag('ios', otherwise: p.job.platform == 'ios'),
        'debugInfoDirectory': ?p.text('debugInfoDirectory'),
      },
    ),
    StepPlanSpec('record.manifest', const {'dartDefineFile'}, (p) async {
      final version = p.job.run.stepVersion;
      if (version?.build == null) return _needsBuild(p);
      return {
        'worktree': p.job.worktree.toJson(),
        'version': '$version',
        'flavors': [?p.job.flavor?.name],
        'dartDefineFile': ?p.text('dartDefineFile'),
      };
    }),
    StepPlanSpec(
      'test',
      const {'paths', 'tags'},
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'branch': p.job.run.ref,
        'baseBranch': p.job.run.project.defaultBaseBranch,
        'flutterVersion': ?p.job.run.app.flutterVersion,
        'paths': p.list('paths'),
        'tags': p.list('tags'),
      },
      capabilities: (_) => const {Capability.flutter},
    ),
    StepPlanSpec(
      'analyze',
      const {'failOn'},
      (p) async => {
        'worktree': p.job.worktree.toJson(),
        'flutterVersion': ?p.job.run.app.flutterVersion,
        'failOn': ?p.text('failOn'),
      },
      capabilities: (_) => const {Capability.flutter},
    ),
    StepPlanSpec(
      'upload.firebase',
      const {
        'artifactName',
        'artifactsFrom',
        'appId',
        'testerEmails',
        'groupAliases',
        'releaseNotes',
      },
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
      const {
        'artifactName',
        'artifactsFrom',
        'packageName',
        'track',
        'status',
        'userFraction',
        'releaseName',
        'releaseNotes',
      },
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
      const {'artifactName', 'artifactsFrom', 'bundleId', 'appleAppId'},
      (p) async {
        final version = _version(p);
        final key = p.job.credential(CredentialKind.ascKey);
        final appleId = p.job.credential(CredentialKind.appleId);
        if (key == null && appleId == null) {
          p.fail(
            'The flavor has no App Store Connect key or Apple ID assigned. '
            'Assign one to the flavor first.',
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
      capabilities: (_) => const {Capability.iosSign},
    ),
    StepPlanSpec('git.releaseBranch', const {}, (p) async {
      final version = p.job.run.version;
      if (version == null) {
        return p.fail('There is no release version: this run bumps none.');
      }
      return {
        'worktree': p.job.worktree.toJson(),
        'version': '${version.name}',
      };
    }),
    StepPlanSpec('git.tag', const {}, (p) async {
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
    StepPlanSpec('git.push', const {'branch', 'tag'}, (p) async {
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
    }),
    StepPlanSpec('github.createPr', const {'title', 'body'}, (p) async {
      final run = p.job.run;
      final version = run.version;
      if (version == null) {
        return p.fail('There is no release version: this run bumps none.');
      }
      final flavor = p.job.flavor;
      return {
        'githubRepoId': run.project.githubRepoId,
        'head': run.model.branchName(version.name, scope: p.job.worktree.scope),
        'base': run.project.defaultBaseBranch,
        'title':
            p.text('title') ??
            'Release ${version.name}${_flavorSuffix(flavor)}',
        'body':
            p.text('body') ??
            'The release branch of ${version.name}, opened by XPath. Merge '
                'it once every store has the release live.',
      };
    }),
    StepPlanSpec(
      'github.mergePr',
      const {},
      (p) async => {
        'releaseId':
            p.job.run.release ??
            p.fail(
              'There is no release to merge: dispatch this workflow with '
              '"release", or with POST /releases/{id}/merge.',
            ),
        'githubRepoId': p.job.run.project.githubRepoId,
      },
    ),
  ];

  // --------------------------------------------------------------- helpers

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

  static Set<Capability> _shorebirdCapabilities(String platform) => {
    Capability.flutter,
    if (platform == 'ios') Capability.iosSign else Capability.android,
  };

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

  static String _requiredSecret(StepPlanning p, CredentialKind kind) =>
      _secretOf(p, kind) ??
      p.fail(
        'The flavor "${p.job.flavor?.name ?? 'default'}" has no '
        '${kind.wire} credential assigned. Assign one to the flavor first.',
      );

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
