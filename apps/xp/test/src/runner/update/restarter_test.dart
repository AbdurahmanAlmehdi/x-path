@Tags(['process'])
library;

import 'package:test/test.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/update/restarter.dart';

void main() {
  test('exits with the restart code under a service manager', () async {
    final said = <String>[];
    var launched = false;
    final restarter = Restarter(
      managed: true,
      launch: (_, _) async {
        launched = true;
        return 0;
      },
    );

    final code = await restarter.restart('/data/current/bin/xp', [
      'runner',
      'start',
    ], said.add);

    expect(code, XpExit.restart);
    expect(code, isNot(0), reason: 'a clean exit would not be restarted');
    expect(launched, isFalse);
    expect(said.single, contains('service manager'));
  });

  test(
    'starts the new version itself otherwise and passes its code on',
    () async {
      final said = <String>[];
      final launches = <(String, List<String>)>[];
      final restarter = Restarter(
        managed: false,
        launch: (executable, arguments) async {
          launches.add((executable, arguments));
          return 17;
        },
      );

      final code = await restarter.restart('/data/current/bin/xp', [
        'runner',
        'start',
        '--data-dir',
        '/data',
      ], said.add);

      expect(code, 17);
      expect(launches, hasLength(1));
      expect(launches.single.$1, '/data/current/bin/xp');
      expect(launches.single.$2, ['runner', 'start', '--data-dir', '/data']);
      expect(said.single, contains('/data/current/bin/xp runner start'));
    },
  );

  test(
    "runs a real program with this process's streams, returns its code",
    () async {
      expect(await launchInheriting('/bin/sh', ['-c', 'exit 7']), 7);
      expect(await launchInheriting('/bin/sh', ['-c', 'exit 0']), 0);
    },
  );

  test('the variable that says a service manager restarts the runner', () {
    expect(runnerManagedVariable, 'XP_RUNNER_MANAGED');
  });
}
