import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';

const _token = 'gho_importedTokenValue123';

void main() {
  late Directory root;
  late String dataDir;
  late WatchedSink out;
  late WatchedSink err;

  /// A `gh` script in [root] that runs [body], and its path.
  String fakeGh(String body, {String folder = 'bin'}) {
    final directory = Directory(p.join(root.path, folder))
      ..createSync(recursive: true);
    final file = File(p.join(directory.path, 'gh'))
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['755', file.path]);
    return file.path;
  }

  // Prints the token only for `gh auth token`.
  String printsToken() => fakeGh(
    '[ "\$1 \$2" = "auth token" ] || exit 2\n'
    '[ "\$GH_PROMPT_DISABLED" = "1" ] || exit 3\n'
    "printf '$_token\\n'",
  );

  Future<int> run(
    List<String> args, {
    Map<String, String> environment = const {},
    List<String> ghFallbackPaths = const [],
  }) => runXpd(
    ['secrets', ...args],
    out: out,
    err: err,
    shutdown: const Stream.empty(),
    environment: environment,
    operatingSystem: 'linux',
    ghFallbackPaths: ghFallbackPaths,
  );

  Future<int> importGh(
    List<String> args, {
    Map<String, String> environment = const {},
    List<String> ghFallbackPaths = const [],
  }) => run(
    ['import-gh', '--data-dir', dataDir, ...args],
    environment: environment,
    ghFallbackPaths: ghFallbackPaths,
  );

  /// The secret store the engine would open on the same data directory.
  SecretStore engineSecrets() => createSecretStore(
    runner: const IoProcessRunner(),
    dataDir: dataDir,
    operatingSystem: 'linux',
    environment: const {},
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('xpd_secrets_');
    dataDir = p.join(root.path, 'data');
    out = WatchedSink();
    err = WatchedSink();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void expectTokenNotPrinted() {
    expect(out.toString(), isNot(contains(_token)));
    expect(err.toString(), isNot(contains(_token)));
  }

  group('xpd secrets import-gh', () {
    test('stores the token of gh where the engine reads it', () async {
      final code = await importGh(['--gh', printsToken()]);

      expect(code, 0);
      expect(out.toString(), 'Imported the GitHub token.\n');
      expect(err.toString(), isEmpty);
      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('never prints the token and never writes it in clear', () async {
      await importGh(['--gh', printsToken()]);

      expectTokenNotPrinted();
      for (final file in Directory(dataDir).listSync().whereType<File>()) {
        expect(
          latin1.decode(file.readAsBytesSync()),
          isNot(contains(_token)),
          reason: file.path,
        );
      }
    });

    test('replaces a token that was imported before', () async {
      await engineSecrets().write(githubTokenSecretKey, 'gho_old');

      await importGh(['--gh', printsToken()]);

      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('finds gh on PATH', () async {
      final gh = printsToken();

      final code = await importGh(
        [],
        environment: {'PATH': '/nonexistent:${p.dirname(gh)}'},
      );

      expect(code, 0);
      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('falls back to the Homebrew locations when PATH has no gh', () async {
      final gh = printsToken();

      final code = await importGh(
        [],
        environment: {'PATH': p.join(root.path, 'empty')},
        ghFallbackPaths: ['/nonexistent/gh', gh],
      );

      expect(code, 0);
      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('prefers --gh to the gh on PATH', () async {
      final onPath = fakeGh(r"printf 'gho_fromPath\n'", folder: 'path');
      final chosen = printsToken();

      await importGh(
        ['--gh', chosen],
        environment: {'PATH': p.dirname(onPath)},
      );

      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('fails when gh is nowhere to be found', () async {
      final code = await importGh(
        [],
        environment: {'PATH': p.join(root.path, 'empty')},
        ghFallbackPaths: ['/nonexistent/one/gh', '/nonexistent/two/gh'],
      );

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        allOf(
          contains('GitHub CLI (gh) was not found'),
          contains('/nonexistent/one/gh, /nonexistent/two/gh'),
          contains('--gh'),
        ),
      );
    });

    test('fails when the gh it is given does not exist', () async {
      final code = await importGh(['--gh', p.join(root.path, 'no-such-gh')]);

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('Cannot run gh'));
      expect(File(p.join(dataDir, 'secrets.enc')).existsSync(), isFalse);
    });

    test('fails, and stores nothing, when gh is not logged in', () async {
      final gh = fakeGh(
        "echo 'You are not logged into any GitHub hosts.' >&2\nexit 1",
      );

      final code = await importGh(['--gh', gh]);

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        allOf(
          contains('not logged into any GitHub hosts'),
          contains('gh auth login'),
        ),
      );
      expect(File(p.join(dataDir, 'secrets.enc')).existsSync(), isFalse);
    });

    test('fails when gh prints something that is not a token', () async {
      final gh = fakeGh('echo "two words"');

      final code = await importGh(['--gh', gh]);

      expect(code, 1);
      expect(err.toString(), contains('did not print a token'));
      expect(File(p.join(dataDir, 'secrets.enc')).existsSync(), isFalse);
    });

    test('fails when the secrets are locked', () async {
      final code = await importGh(
        ['--gh', printsToken()],
        environment: {'CREDENTIALS_DIRECTORY': p.join(root.path, 'nowhere')},
      );

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('the secrets are locked'));
      expectTokenNotPrinted();
    });

    test('fails when the secret store cannot be written', () async {
      File(dataDir).createSync(); // a file where the directory should be

      final code = await importGh(['--gh', printsToken()]);

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('could not be stored'));
      expectTokenNotPrinted();
    });

    test('takes the data directory from the environment', () async {
      final code = await run(
        ['import-gh', '--gh', printsToken()],
        environment: {dataDirectoryEnvironmentKey: dataDir},
      );

      expect(code, 0);
      expect(await engineSecrets().read(githubTokenSecretKey), _token);
    });

    test('describes itself', () async {
      final code = await run(['import-gh', '--help']);

      expect(code, 0);
      expect(
        out.toString(),
        allOf(
          contains('never printed'),
          contains('--gh'),
          contains('--data-dir'),
        ),
      );
    });
  });

  test('xpd secrets --help lists import-gh', () async {
    final code = await run(['--help']);

    expect(code, 0);
    expect(out.toString(), contains('import-gh'));
  });

  test('xpd --help lists secrets', () async {
    final code = await runXpd(
      ['--help'],
      out: out,
      err: err,
      shutdown: const Stream.empty(),
      environment: const {},
      operatingSystem: 'linux',
    );

    expect(code, 0);
    expect(out.toString(), contains('secrets'));
  });

  test('xpd secrets without a command prints the usage', () async {
    final code = await run([]);

    expect(code, 64);
    expect(err.toString(), contains('import-gh'));
  });
}
