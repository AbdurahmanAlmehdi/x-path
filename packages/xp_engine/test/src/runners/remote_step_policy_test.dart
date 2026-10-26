import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('RemoteStepPolicy', () {
    test('keeps every upload on the engine (D-09)', () {
      for (final kind in [
        'upload.appStore',
        'upload.play',
        'upload.firebase',
        'upload.anythingNew',
      ]) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isTrue, reason: kind);
      }
    });

    test('keeps what pushes, tags or talks to GitHub on the engine', () {
      for (final kind in [
        'git.push',
        'git.tag',
        'git.releaseBranch',
        'github.createPr',
        'github.mergePr',
      ]) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isTrue, reason: kind);
      }
    });

    test('keeps the gate, the guard and the test baseline on the engine', () {
      for (final kind in ['gate', 'guard', 'test']) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isTrue, reason: kind);
      }
    });

    test('keeps a rollout change and a patch move on the engine', () {
      for (final kind in ['store.rollout', 'shorebird.track']) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isTrue, reason: kind);
        expect(RemoteStepPolicy.canRunRemotely([kind]), isFalse, reason: kind);
      }
    });

    test('lets Shorebird go: its key travels like signing material', () {
      for (final kind in ['shorebird.release', 'shorebird.patch']) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isFalse, reason: kind);
      }
    });

    test('lets the building, testing and archiving steps go', () {
      for (final kind in [
        'git.checkout',
        'version.bump',
        'build.android',
        'build.ios',
        'build.verifyCompiledConfig',
        'ios.stripAndReexport',
        'symbols.archive',
        'record.manifest',
        'analyze',
        'command',
      ]) {
        expect(RemoteStepPolicy.isEngineOnly(kind), isFalse, reason: kind);
      }
    });

    test('a job goes only if every step may', () {
      expect(RemoteStepPolicy.canRunRemotely(const []), isTrue);
      expect(
        RemoteStepPolicy.canRunRemotely(['git.checkout', 'build.android']),
        isTrue,
      );
      expect(
        RemoteStepPolicy.canRunRemotely(['build.android', 'upload.play']),
        isFalse,
      );
    });

    test('names the steps that keep a job on the engine, sorted, once', () {
      expect(
        RemoteStepPolicy.engineOnlyIn([
          'build.android',
          'upload.play',
          'guard',
          'upload.play',
        ]),
        ['guard', 'upload.play'],
      );
      expect(RemoteStepPolicy.engineOnlyIn(['shorebird.patch']), isEmpty);
    });
  });
}
