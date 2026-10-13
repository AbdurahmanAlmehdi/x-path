/// Which packages one workspace package may depend on.
///
/// A dependency is a `pubspec.yaml` entry or an `import` / `export` directive
/// in `lib/`, `test/`, `bin/` or `integration_test/`.
class LayerRule {
  /// Creates a rule.
  const new({required this.workspace, this.external});

  /// The workspace packages this package may depend on.
  final Set<String> workspace;

  /// The packages outside the workspace this package may depend on, or `null`
  /// when any package is allowed.
  final Set<String>? external;
}

/// Test and lint tooling every package may use.
const _tooling = {
  'bloc_lint',
  'bloc_test',
  'build_runner',
  'flutter_test',
  'mocktail',
  'test',
  'very_good_analysis',
};

/// The dependency direction from the architecture section of the plan.
///
/// `xp_engine` and `xp_api` are framework-free, so their external packages are
/// an allowlist. Adding a package there is a deliberate, reviewed change.
const layerRules = <String, LayerRule>{
  'xp_api': LayerRule(
    workspace: {},
    external: {
      ..._tooling,
      'collection',
      'equatable',
      'json_annotation',
      'json_schema',
      'json_serializable',
      'meta',
      // `package:xp_api/testing.dart` (contract-test helper) reads openapi.yaml.
      'yaml',
    },
  ),
  'xp_engine': LayerRule(
    workspace: {'xp_api'},
    external: {
      ..._tooling,
      'collection',
      'crypto',
      'equatable',
      'meta',
      // The scanner reads pubspec, flavorizr, Shorebird and workflow YAML.
      'yaml',
    },
  ),
  'xp_client': LayerRule(workspace: {'xp_api'}),
  'xp_repositories': LayerRule(workspace: {'xp_api', 'xp_client'}),
  // `xp_fake_asc` and `xp_fake_play` are fake store servers: tests of the
  // store adapters run against them.
  'xp_adapters': LayerRule(
    workspace: {'xp_api', 'xp_engine', 'xp_fake_asc', 'xp_fake_play'},
  ),
  'xp_secrets': LayerRule(workspace: {'xp_api', 'xp_engine'}),
  'xp_macos_services': LayerRule(workspace: {}),
  // Fake store servers for tests and the end-to-end scripts (tool/e2e). They
  // know nothing of the engine.
  'xp_fake_asc': LayerRule(workspace: {}),
  'xp_fake_play': LayerRule(workspace: {}),
  // The engine entrypoint wires every implementation.
  // `xp_fake_asc` and `xp_fake_play` are for the tests of the store wiring.
  'xpd': LayerRule(
    workspace: {
      'xp_adapters',
      'xp_api',
      'xp_engine',
      'xp_fake_asc',
      'xp_fake_play',
      'xp_secrets',
    },
  ),
  // `xp runner` executes jobs with the shared step runner (Phase 14b).
  'xp': LayerRule(
    workspace: {
      'xp_adapters',
      'xp_api',
      'xp_client',
      'xp_engine',
      'xp_secrets',
    },
  ),
  // The desktop talks to the engine through repositories only: no engine,
  // adapters or secrets.
  'xp_desktop': LayerRule(
    workspace: {'xp_api', 'xp_client', 'xp_macos_services', 'xp_repositories'},
  ),
  'xp_tool': LayerRule(workspace: {}),
};
