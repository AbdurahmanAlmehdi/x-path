import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The app of the workflow tests: Android and iOS, a dev flavor and a prod
/// flavor that Shorebird patches.
const demoApp = AppProfile(
  name: 'demo',
  path: '.',
  version: '1.2.3+45',
  flutterVersion: '3.47.6',
  hasAndroid: true,
  hasIos: true,
  flavors: [
    FlavorProfile(
      name: 'dev',
      entrypoint: 'lib/main_dev.dart',
      androidAppId: 'ly.demo.dev',
      iosBundleId: 'ly.demo.dev',
      versionFiles: ['pubspec.yaml', 'ios/Runner/Info-dev.plist'],
    ),
    FlavorProfile(
      name: 'prod',
      entrypoint: 'lib/main_prod.dart',
      androidAppId: 'ly.demo',
      iosBundleId: 'ly.demo',
      prod: true,
      shorebird: true,
      shorebirdAppId: 'sb-prod',
      versionFiles: ['pubspec.yaml', 'ios/Runner/Info-prod.plist'],
    ),
  ],
);

/// A project with [apps] (the demo app by default).
ProjectRecord demoProject({
  String id = 'prj_1',
  List<AppProfile> apps = const [demoApp],
  int repoId = 42,
}) => ProjectRecord(
  id: id,
  githubRepoId: repoId,
  fullName: 'octo/demo',
  remote: 'https://github.com/octo/demo.git',
  githubDefaultBranch: 'main',
  scan: ProjectProfile(apps: apps),
  findings: const [],
  scannedAt: DateTime.utc(2026, 10, 13),
);

/// The credential flavor of the demo app's flavor [name].
CredentialFlavor demoFlavor(String name, {String project = 'prj_1'}) =>
    CredentialFlavor(
      id: 'flv_$name',
      projectId: project,
      appPath: '.',
      name: name,
    );

/// A credential of [kind] for the flavor [flavor].
CredentialRecord demoCredential(
  CredentialFlavor flavor,
  CredentialKind kind, {
  String? account,
}) => CredentialRecord(
  id: 'crd_${flavor.name}_${kind.wire}',
  flavor: flavor,
  kind: kind,
  secretKey: 'credential.${flavor.name}.${kind.wire}',
  account: account,
);
