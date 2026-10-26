import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_paths.dart';

void main() {
  test('lays out the data directory', () {
    const paths = RunnerPaths('/data/runner');

    expect(paths.root, '/data/runner');
    expect(paths.identityFile, '/data/runner/runner.json');
    expect(paths.source, '/data/runner/source');
    expect(paths.jobs, '/data/runner/jobs');
    expect(paths.jobDirectory('job_1'), '/data/runner/jobs/job_1');
    expect(paths.flutterToolchains, '/data/runner/toolchains/flutter');
    expect(
      paths.iosLinuxToolchains,
      '/data/runner/toolchains/flutter-ios-linux',
    );
    expect(paths.fallbackSecrets, '/data/runner/secrets');
    expect(paths.keychains, '/data/runner/keychains');
    expect(paths.state, '/data/runner/state');
  });

  test('lays out the versions of xp and the link to the current one', () {
    const paths = RunnerPaths('/data/runner');

    expect(paths.versions, '/data/runner/versions');
    expect(paths.versionDirectory('1.2.3'), '/data/runner/versions/1.2.3');
    expect(paths.currentLink, '/data/runner/current');
    expect(paths.currentExecutable, '/data/runner/current/bin/xp');
    expect(paths.updates, '/data/runner/updates');
    expect(paths.updateState, '/data/runner/update.json');
    expect(paths.serviceLogs, '/data/runner/service-logs');
  });

  group('the default data directory', () {
    test('is named by XP_RUNNER_DATA_DIR', () {
      final paths = RunnerPaths.fromEnvironment({
        RunnerPaths.dataDirVariable: '/srv/runner',
        'XDG_DATA_HOME': '/xdg',
      }, '/home/me');

      expect(paths.root, '/srv/runner');
    });

    test('follows XDG_DATA_HOME', () {
      final paths = RunnerPaths.fromEnvironment({
        'XDG_DATA_HOME': '/xdg',
      }, '/home/me');

      expect(paths.root, p.join('/xdg', 'xpath', 'runner'));
    });

    test('is in the home directory otherwise', () {
      expect(
        RunnerPaths.fromEnvironment({}, '/home/me').root,
        '/home/me/.local/share/xpath/runner',
      );
      expect(
        RunnerPaths.fromEnvironment({
          RunnerPaths.dataDirVariable: '',
          'XDG_DATA_HOME': '',
        }, '/home/me').root,
        '/home/me/.local/share/xpath/runner',
      );
    });
  });
}
