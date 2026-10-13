import 'package:xp_engine/xp_engine.dart';

import 'stub_git.dart';
import 'version_fixtures.dart';

/// The commit every guard test dispatches.
const String dispatchedSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Another commit.
const String otherSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A mirror that does not exist; [StubGit] never opens it.
const mirror = GitMirror(githubRepoId: 42, path: '/mirrors/42.git');

/// A tag of a release on [commit].
GitTagInfo tag(String name, [String? commit]) =>
    GitTagInfo(name: name, commit: commit ?? 'f' * 40);

/// The files of the Mataa customer app at version [version], with the plists
/// that carry literal versions.
Map<String, String> customerApp(String version, {String plistVersion = ''}) {
  final parsed = AppVersion.parse(version);
  final name = '${parsed.name}';
  final build = '${parsed.build}';
  return {
    'pubspec.yaml': pubspec(version),
    'ios/Runner/Info.plist': plist(name, build),
    'ios/Runner/Info-Dev.plist': plist(name, build),
    'android/app/build.gradle.kts': gradle(targetSdk: '35'),
  };
}

/// A guard request over [files] with a [StubGit].
({GuardRequest request, InMemoryWorkspace workspace, StubGit git})
guardRequest({
  Map<String, String>? files,
  StubGit? git,
  List<String> versionFiles = const [
    'pubspec.yaml',
    'ios/Runner/Info.plist',
    'ios/Runner/Info-Dev.plist',
  ],
  String appPath = '.',
  ReleaseModel model = const ReleaseModel(),
  TagScope scope = const TagScope(),
  String? releaseVersion,
  String? iosBundleId = 'com.mataa.app',
  String? androidAppId = 'com.mataa.app',
  String? shorebirdAppId,
  List<GuardCheckName> checks = const [],
}) {
  final workspace = InMemoryWorkspace(files ?? customerApp('5.4.1+3283'));
  final stub = git ?? StubGit();
  final request = GuardRequest(
    input: GuardInput(
      checks: checks,
      worktree: ReleaseWorktree(
        path: '/work/job_1',
        mirror: mirror,
        sha: dispatchedSha,
        appPath: appPath,
        versionFiles: versionFiles,
        releaseModel: model,
        scope: scope,
      ),
      releaseVersion: releaseVersion,
      iosBundleId: iosBundleId,
      androidAppId: androidAppId,
      shorebirdAppId: shorebirdAppId,
    ),
    workspace: workspace,
    git: stub,
  );
  return (request: request, workspace: workspace, git: stub);
}

/// An `android/app/build.gradle.kts` as `flutter create` writes it, with the
/// target API level set to [targetSdk].
String gradle({required String targetSdk}) =>
    '''
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mataa.app"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.mataa.app"
        minSdk = flutter.minSdkVersion
        // targetSdk = 21 would be an old comment.
        targetSdk = $targetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
''';
