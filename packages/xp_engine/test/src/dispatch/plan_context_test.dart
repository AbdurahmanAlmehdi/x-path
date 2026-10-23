import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/scripted_git.dart';
import '../../helpers/workflow_fixtures.dart';

const _mirror = GitMirror(githubRepoId: 42, path: '/mirrors/42.git');

RunContext _run({
  AppVersion? version,
  AppVersion? current,
  AppVersion? release,
  String? releaseId,
}) => RunContext(
  runId: 'run_1',
  project: demoProject(),
  app: demoApp,
  flavors: demoApp.flavors,
  platforms: const ['android'],
  ref: 'main',
  sha: 'a' * 40,
  mirror: _mirror,
  model: const ReleaseModel(),
  worktreeAt: ScriptedGit.pathOf,
  inputs: const {'notes': 'hi'},
  bump: 'keep',
  version: version,
  build: version?.build,
  current: current,
  releaseVersion: release,
  patch: release == null ? null : 2,
  release: releaseId,
);

StepPlanning _planning(Map<String, Object?> values) => StepPlanning(
  kind: 'guard',
  job: JobContext(
    run: _run(),
    jobId: 'job_1',
    worktree: const ReleaseWorktree(path: '/w', mirror: _mirror, sha: 'a'),
    flavorValue: null,
  ),
  values: values,
  position: const SourcePosition(7, 3),
);

void main() {
  group('RunContext', () {
    test('shows a workflow what the dispatch decided', () {
      final run = _run(version: AppVersion.parse('1.2.4+9'));

      expect(run.scope, {
        'app': {
          'name': 'demo',
          'path': '.',
          'hasIos': true,
          'hasAndroid': true,
          'version': '1.2.3+45',
        },
        'project': {
          'id': 'prj_1',
          'fullName': 'octo/demo',
          'baseBranch': 'main',
        },
        'ref': 'main',
        'sha': 'a' * 40,
        'release': null,
        'version': '1.2.4',
        'build': 9,
        'bump': 'keep',
        'releaseVersion': null,
        'patch': null,
        'platforms': ['android'],
        'flavors': ['dev', 'prod'],
        'inputs': {'notes': 'hi'},
      });
    });

    test('shows the release a run belongs to', () {
      expect(_run(releaseId: 'rel_1').scope['release'], 'rel_1');
      expect(_run().scope['release'], isNull);
    });

    test('shows the release a patch applies to', () {
      final run = _run(release: AppVersion.parse('1.2.0+30'));

      expect(run.scope['releaseVersion'], '1.2.0+30');
      expect(run.scope['patch'], 2);
      expect(run.scope['version'], isNull);
    });

    test(
      'gives its steps the release, else the new version, else the current',
      () {
        final release = AppVersion.parse('1.2.0+30');
        final bumped = AppVersion.parse('1.2.4+9');
        final current = AppVersion.parse('1.2.3+45');

        expect(
          _run(release: release, version: bumped, current: current).stepVersion,
          release,
        );
        expect(_run(version: bumped, current: current).stepVersion, bumped);
        expect(_run(current: current).stepVersion, current);
        expect(_run().stepVersion, isNull);
      },
    );
  });

  group('JobContext', () {
    test('adds the matrix cell to the scope', () {
      final dev = demoApp.flavors.first;
      final context = JobContext(
        run: _run(),
        jobId: 'job_1',
        worktree: const ReleaseWorktree(path: '/w', mirror: _mirror, sha: 'a'),
        platform: 'ios',
        flavor: dev,
        flavorValue: flavorScope(dev, const []),
      );

      expect(context.scope['platform'], 'ios');
      expect((context.scope['flavor']! as Map)['name'], 'dev');
      expect(context.scope['sha'], 'a' * 40);
    });

    test('has no platform or flavor without a matrix', () {
      final context = _planning(const {}).job;

      expect(context.scope.containsKey('platform'), isFalse);
      expect(context.scope.containsKey('flavor'), isFalse);
    });

    test('finds a credential by kind', () {
      final flavor = demoFlavor('dev');
      final key = demoCredential(flavor, CredentialKind.ascKey);
      final context = JobContext(
        run: _run(),
        jobId: 'job_1',
        worktree: const ReleaseWorktree(path: '/w', mirror: _mirror, sha: 'a'),
        flavorValue: null,
        credentials: [key],
      );

      expect(context.credential(CredentialKind.ascKey), key);
      expect(context.credential(CredentialKind.playSa), isNull);
    });

    test('shows a flavor with what it has', () {
      final prod = demoApp.flavors.last;
      final flavor = flavorScope(prod, [
        demoCredential(demoFlavor('prod'), CredentialKind.playSa),
      ]);

      expect(flavor, {
        'name': 'prod',
        'implicit': false,
        'prod': true,
        'shorebird': true,
        'entrypoint': 'lib/main_prod.dart',
        'iosBundleId': 'ly.demo',
        'androidAppId': 'ly.demo',
        'shorebirdAppId': 'sb-prod',
        'firebaseAppId': <String, String>{},
        'appleAppId': null,
        'credentials': {'play_sa': true},
      });
      expect(
        flavorScope(
          prod.copyWith(
            firebaseAppId: () => {'android': '1:1:android:a'},
            appleAppId: () => '9',
          ),
          const [],
        ),
        containsPair('firebaseAppId', {'android': '1:1:android:a'}),
      );
    });
  });

  group('StepPlanning', () {
    Matcher fails(String message) => throwsA(
      isA<DispatchException>().having(
        (e) => e.message,
        'message',
        'Line 7, guard: $message',
      ),
    );

    test('reads typed values', () {
      final planning = _planning({
        'text': 'x',
        'flag': true,
        'list': ['a', 'b'],
        'number': 0.5,
        'map': {'a': 'b'},
        'any': 3,
      });

      expect(planning.text('text'), 'x');
      expect(planning.text('missing'), isNull);
      expect(planning.requireText('text'), 'x');
      expect(planning.flag('flag'), isTrue);
      expect(planning.flag('missing'), isFalse);
      expect(planning.flag('missing', otherwise: true), isTrue);
      expect(planning.list('list'), ['a', 'b']);
      expect(planning.list('missing'), isEmpty);
      expect(planning.number('number'), 0.5);
      expect(planning.number('missing'), isNull);
      expect(planning.strings('map'), {'a': 'b'});
      expect(planning.strings('missing'), isEmpty);
      expect(planning.raw('any'), 3);
    });

    test('names the line and the step when a value is not right', () {
      final planning = _planning({
        'n': 3,
        's': 'x',
        'l': [1],
        'm': {'a': 1},
      });

      expect(() => planning.text('n'), fails('"n" must be a string.'));
      expect(
        () => planning.requireText('missing'),
        fails('"missing" is needed: give it under "with".'),
      );
      expect(() => planning.flag('s'), fails('"s" must be true or false.'));
      expect(() => planning.list('n'), fails('"n" must be a list of strings.'));
      expect(() => planning.list('l'), fails('"l" must be a list of strings.'));
      expect(() => planning.number('s'), fails('"s" must be a number.'));
      expect(
        () => planning.strings('l'),
        fails('"l" must be a mapping of strings.'),
      );
      expect(
        () => planning.strings('m'),
        fails('"m" must be a mapping of strings.'),
      );
      expect(() => planning.fail('nope'), fails('nope'));
    });
  });
}
