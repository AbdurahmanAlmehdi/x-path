import 'package:test/test.dart';
import 'package:xp/src/runner/no_secrets.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const secrets = NoSecrets();

  test('has no secret, whatever is asked for', () async {
    expect(await secrets.read('github.token'), isNull);
    expect(await secrets.readBytes('github.token'), isNull);
    expect(secrets.status, SecretsStatus.unlocked);
    expect(secrets.statusChanges, emitsDone);
  });

  test('keeps nothing that is written to it', () async {
    await secrets.write('k', 'v');
    await secrets.writeBytes('k', [1]);
    await secrets.delete('k');

    expect(await secrets.read('k'), isNull);
  });
}
