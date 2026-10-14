import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUpAll(registerFallbacks);
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('storage report', () {
    test('prints the categories, the totals and the retention', () async {
      when(() => env.client.getStorage())
          .thenAnswer((_) async => sample.storageReport());

      await env.runOk(['storage', 'report']);

      expect(env.logger.out, contains('artifacts  3.0 MB  1.0 KB'));
      expect(env.logger.out, contains('total: 3.0 MB, 1.0 KB can be freed'));
      expect(
        env.logger.out,
        contains('last 5 builds per flavor, 90 days of logs'),
      );
    });

    test('with --json prints the report', () async {
      when(() => env.client.getStorage())
          .thenAnswer((_) async => sample.storageReport());

      await env.runOk(['--json', 'storage', 'report']);

      expect(jsonDecode(env.logger.infos.single), contains('categories'));
    });
  });

  group('storage free', () {
    test('is a dry run unless told to apply', () async {
      when(() => env.client.freeStorage(any())).thenAnswer(
        (_) async => const FreeSpaceResult(
          dryRun: true,
          categories: [
            FreedCategory(
              category: StorageCategory.logs,
              bytes: 2048,
              items: 3,
            ),
          ],
        ),
      );

      await env.runOk(['storage', 'free']);

      final request =
          verify(() => env.client.freeStorage(captureAny())).captured.single
              as FreeSpaceRequest;
      expect(request.dryRun, isTrue);
      expect(request.categories, isNull);
      expect(env.logger.out, contains('Would free 2.0 KB (pass --apply'));
      expect(env.logger.out, contains('logs      2.0 KB  3'));
    });

    test('frees the space with --apply, for the categories named', () async {
      when(() => env.client.freeStorage(any())).thenAnswer(
        (_) async => const FreeSpaceResult(dryRun: false, categories: []),
      );

      await env.runOk([
        'storage',
        'free',
        '--apply',
        '--category',
        'logs',
        '--category',
        'worktrees',
      ]);

      final request =
          verify(() => env.client.freeStorage(captureAny())).captured.single
              as FreeSpaceRequest;
      expect(request.dryRun, isFalse);
      expect(request.categories, [
        StorageCategory.logs,
        StorageCategory.worktrees,
      ]);
      expect(env.logger.out, contains('Freed 0 B:'));
    });

    test('exits 1 and says what it could not free', () async {
      when(() => env.client.freeStorage(any())).thenAnswer(
        (_) async => const FreeSpaceResult(
          dryRun: false,
          categories: [],
          failures: ['mirror: busy'],
        ),
      );

      expect(await env.run(['storage', 'free', '--apply']), 1);

      expect(env.logger.out, contains('could not free: mirror: busy'));
    });
  });

  group('storage retention', () {
    test('shows the retention', () async {
      when(() => env.client.getRetention())
          .thenAnswer((_) async => const RetentionSettings());

      await env.runOk(['storage', 'retention']);

      expect(env.logger.out, 'keep 5 builds per flavor, 90 days of logs');
      verifyNever(() => env.client.setRetention(any()));
    });

    test('changes one value and keeps the other', () async {
      when(() => env.client.getRetention())
          .thenAnswer((_) async => const RetentionSettings());
      when(() => env.client.setRetention(any()))
          .thenAnswer((_) async => const RetentionSettings(keepPerFlavor: 3));

      await env.runOk(['storage', 'retention', '--keep', '3']);

      final settings =
          verify(() => env.client.setRetention(captureAny())).captured.single
              as RetentionSettings;
      expect(settings, const RetentionSettings(keepPerFlavor: 3));
      expect(env.logger.out, 'keep 3 builds per flavor, 90 days of logs');
    });

    test('changes the days of logs', () async {
      when(() => env.client.getRetention())
          .thenAnswer((_) async => const RetentionSettings());
      when(() => env.client.setRetention(any()))
          .thenAnswer((_) async => const RetentionSettings(logDays: 30));

      await env.runOk(['storage', 'retention', '--log-days', '30']);

      verify(
        () => env.client.setRetention(const RetentionSettings(logDays: 30)),
      ).called(1);
    });

    test('refuses a count that is not a number', () async {
      expect(await env.run(['storage', 'retention', '--keep', 'x']), 64);
      expect(await env.run(['storage', 'retention', '--log-days', '-1']), 64);
    });
  });

  group('artifacts', () {
    test('list prints a table', () async {
      when(() => env.client.listJobArtifacts('job_1'))
          .thenAnswer((_) async => [sample.artifact()]);

      await env.runOk(['artifacts', 'list', 'job_1']);

      expect(env.logger.out, contains('art_1  apk   app.apk  3 B'));
      expect(env.logger.out, contains('yes'));
    });

    test('list says when there are none', () async {
      when(() => env.client.listJobArtifacts('job_1'))
          .thenAnswer((_) async => []);

      await env.runOk(['artifacts', 'list', 'job_1']);

      expect(env.logger.out, 'No artifacts.');
    });

    group('download', () {
      late Directory directory;
      final bytes = utf8.encode('abc');
      final digest = crypto.sha256.convert(bytes).toString();

      setUp(() {
        directory = Directory.systemTemp.createTempSync('xp_artifacts');
        when(() => env.client.getArtifact('art_1'))
            .thenAnswer((_) async => sample.artifact());
      });
      tearDown(() => directory.deleteSync(recursive: true));

      void serve({String? sha256}) {
        when(() => env.client.downloadArtifact('art_1')).thenAnswer(
          (_) async => ArtifactDownload(
            content: Stream.value(bytes),
            sha256: sha256 ?? digest,
            length: bytes.length,
          ),
        );
      }

      test('saves into a folder under the artifact name', () async {
        serve();

        await env.runOk([
          'artifacts',
          'download',
          'art_1',
          '--output',
          directory.path,
        ]);

        expect(File('${directory.path}/app.apk').readAsBytesSync(), bytes);
        expect(env.logger.out, contains('app.apk'));
        expect(env.logger.out, contains(digest));
      });

      test('saves to a file name', () async {
        serve();

        await env.runOk([
          'artifacts',
          'download',
          'art_1',
          '-o',
          '${directory.path}/mine.bin',
        ]);

        expect(File('${directory.path}/mine.bin').existsSync(), isTrue);
      });

      test('saves into the current folder by default', () async {
        serve();
        final saved = File('app.apk');
        addTearDown(() {
          if (saved.existsSync()) saved.deleteSync();
        });

        await env.runOk(['--json', 'artifacts', 'download', 'art_1']);

        expect(saved.readAsBytesSync(), bytes);
        expect((jsonDecode(env.logger.infos.single) as Map)['sha256'], digest);
      });

      test('refuses a file that is not what the engine announced', () async {
        serve(sha256: 'f' * 64);

        final code = await env.run([
          'artifacts',
          'download',
          'art_1',
          '-o',
          directory.path,
        ]);

        expect(code, 1);
        expect(
          env.logger.errors.single,
          contains('not what the engine announced'),
        );
        expect(File('${directory.path}/app.apk').existsSync(), isFalse);
      });
    });
  });
}
