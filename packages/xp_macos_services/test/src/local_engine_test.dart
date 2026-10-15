import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  late Directory root;
  late String executable;
  late List<List<String>> runs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_engine_');
    executable = p.join(root.path, 'xpd', 'bin', 'xpd');
    File(executable).createSync(recursive: true);
    runs = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundledLocalEngine engine(ProcessResult result) => BundledLocalEngine(
    executable: executable,
    run: (command, arguments) async {
      runs.add([command, ...arguments]);
      return result;
    },
  );

  test('makes an app token with xpd token create', () async {
    final token = await engine(
      ProcessResult(1, 0, 'xpt_abc-DEF_123\n', 'Created app token'),
    ).createAppToken(name: 'XPath app');
    expect(token, 'xpt_abc-DEF_123');
    expect(runs, [
      [executable, 'token', 'create', '--name', 'XPath app', '--kind', 'app'],
    ]);
  });

  test('passes on what the engine said when it fails', () async {
    await expectLater(
      engine(ProcessResult(1, 64, '', 'database is locked\n'))
          .createAppToken(name: 'x'),
      throwsA(
        isA<LocalEngineException>().having(
          (error) => error.message,
          'message',
          'database is locked',
        ),
      ),
    );
    await expectLater(
      engine(ProcessResult(1, 0, 'not a token', '')).createAppToken(name: 'x'),
      throwsA(
        isA<LocalEngineException>().having(
          (error) => error.toString(),
          'toString',
          contains('exited 0'),
        ),
      ),
    );
  });

  test('says when the engine cannot be started', () async {
    final failing = BundledLocalEngine(
      executable: executable,
      run: (command, arguments) async =>
          throw ProcessException(command, arguments, 'Permission denied'),
    );
    await expectLater(
      failing.createAppToken(name: 'x'),
      throwsA(isA<LocalEngineException>()),
    );
  });

  test('says when there is no engine in this build', () async {
    File(executable).deleteSync();
    final missing = BundledLocalEngine(executable: executable);
    expect(missing.isBundled, isFalse);
    await expectLater(
      missing.createAppToken(name: 'x'),
      throwsA(isA<LocalEngineException>()),
    );
  });
}
