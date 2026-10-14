import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/secrets/lease_secret_store.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp_engine/xp_engine.dart';

class _Masker implements OutputMasker {
  final secrets = <String>[];

  @override
  void add(String secret) => secrets.add(secret);

  @override
  StreamMasker newStream() => throw UnimplementedError();
}

void main() {
  late Directory directory;
  late SecretArea area;
  late _Masker masker;
  late List<String> asked;
  late Map<String, List<int>?> answers;

  LeaseSecretStore store({Iterable<String> granted = const ['ks', 'pw']}) =>
      LeaseSecretStore(
        jobId: 'job_1',
        granted: granted,
        area: area,
        masker: masker,
        request: (key) async {
          asked.add(key);
          return answers[key];
        },
      );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('xp_lease_secrets_');
    addTearDown(() => directory.deleteSync(recursive: true));
    area = SecretArea(
      SecretLocations(
        active: p.join(directory.path, 'secrets'),
        all: [p.join(directory.path, 'secrets')],
      ),
    );
    await area.wipeAll();
    masker = _Masker();
    asked = [];
    answers = {
      'ks': [0xfe, 0xed, 0x00, 0xff],
      'pw': utf8.encode('s3cret'),
    };
  });

  test(
    'asks the engine once per key and keeps the answer in the job folder',
    () async {
      final secrets = store();

      final first = await secrets.readBytes('ks');
      final second = await secrets.readBytes('ks');

      expect(first, [0xfe, 0xed, 0x00, 0xff]);
      expect(second, first);
      expect(asked, ['ks']);
      expect(await area.recall('job_1', 'ks'), first);
    },
  );

  test('reads what an earlier store of the job kept, without asking', () async {
    await store().readBytes('pw');
    asked.clear();

    final text = await store().read('pw');

    expect(text, 's3cret');
    expect(asked, isEmpty);
  });

  test('asks once when several steps want the same key together', () async {
    final secrets = store();

    final both = await Future.wait([
      secrets.readBytes('pw'),
      secrets.readBytes('pw'),
    ]);

    expect(both[0], both[1]);
    expect(asked, ['pw']);
  });

  test('never asks for a key the offer did not list', () async {
    final secrets = store(granted: const ['ks']);

    expect(await secrets.readBytes('github.token'), isNull);
    expect(await secrets.read('github.token'), isNull);
    expect(asked, isEmpty);
  });

  test('has nothing when the engine refuses', () async {
    answers['ks'] = null;

    expect(await store().readBytes('ks'), isNull);
    expect(await area.recall('job_1', 'ks'), isNull);
  });

  test('teaches the masker the text of a secret, not a keystore', () async {
    final secrets = store();

    await secrets.readBytes('ks');
    await secrets.read('pw');

    expect(masker.secrets, ['s3cret']);
  });

  test('does not teach the masker an empty secret', () async {
    answers['pw'] = <int>[];

    await store().readBytes('pw');

    expect(masker.secrets, isEmpty);
  });

  test('refuses to read a binary secret as text', () async {
    await expectLater(store().read('ks'), throwsA(isA<SecretStoreException>()));
  });

  test('is read only', () async {
    final secrets = store();

    expect(secrets.status, SecretsStatus.unlocked);
    expect(secrets.statusChanges, emitsDone);
    await expectLater(
      secrets.write('k', 'v'),
      throwsA(isA<SecretStoreException>()),
    );
    await expectLater(
      secrets.writeBytes('k', [1]),
      throwsA(isA<SecretStoreException>()),
    );
    await expectLater(
      secrets.delete('k'),
      throwsA(isA<SecretStoreException>()),
    );
  });
}
