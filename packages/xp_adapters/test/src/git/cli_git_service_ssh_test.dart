@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/git_fixture.dart';
import '../../helpers/memory_secret_store.dart';

/// An `ssh` that serves the repository on this machine, as a git host would,
/// or answers as SSH does for a host key it has not seen, a host key that
/// changed, or a key the host does not take (`FAKE_SSH_MODE`).
const _fakeSsh = r'''
#!/bin/sh
echo "$@" >> "$FAKE_SSH_LOG"
case "$FAKE_SSH_MODE" in
  new)
    echo "Warning: Permanently added 'host' (ED25519) to the list of known hosts." >&2
    ;;
  changed)
    echo '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' >&2
    echo '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' >&2
    echo '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' >&2
    echo 'Host key verification failed.' >&2
    exit 255
    ;;
  denied)
    echo "$FAKE_SSH_USER_HOST: Permission denied (publickey)." >&2
    exit 255
    ;;
esac
eval "command=\${$#}"
exec sh -c "$(echo "$command" | sed 's/^git-upload-pack/git upload-pack/')"
''';

void main() {
  // One repository and one fake ssh for every test, as git setup is slow;
  // each test starts with an empty ssh log.
  late GitFixture fixture;
  late Directory bin;
  late String log;

  setUpAll(() {
    fixture = GitFixture.create();
    fixture
      ..commit('a.txt', 'one')
      ..git(['checkout', '--quiet', '-b', 'develop'])
      ..commit('b.txt', 'two')
      ..push('develop')
      ..git([
        'symbolic-ref',
        'HEAD',
        'refs/heads/develop',
      ], cwd: fixture.origin);
    bin = Directory(p.join(fixture.root.path, 'bin'))..createSync();
    final ssh = File(p.join(bin.path, 'ssh'))
      ..writeAsStringSync(_fakeSsh.substring(1));
    Process.runSync('chmod', ['+x', ssh.path]);
    log = p.join(fixture.root.path, 'ssh.log');
  });
  tearDownAll(() => fixture.dispose());
  setUp(() {
    if (File(log).existsSync()) File(log).deleteSync();
  });

  CliGitService serviceIn(String mode, {String userHost = 'git@host'}) =>
      CliGitService(
        runner: IoProcessRunner(
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'FAKE_SSH_MODE': mode,
            'FAKE_SSH_LOG': log,
            'FAKE_SSH_USER_HOST': userHost,
          },
        ),
        secrets: MemorySecretStore(),
        dataDir: p.join(fixture.root.path, 'data'),
      );

  String sshUrl([String host = 'git.example.com']) =>
      'git@$host:${fixture.origin}';

  Future<String> failureOf(CliGitService service, String url) async {
    try {
      await service.lsRemote(url);
    } on GitException catch (error) {
      return error.message;
    }
    fail('ls-remote of $url did not fail');
  }

  test('records a host key it has not seen and reads the repository', () async {
    final service = serviceIn('new');

    expect(await service.lsRemote(sshUrl()), 'develop');

    final mirror = await service.ensureMirror(
      key: GitRemote.parse(sshUrl())!.sourceKey,
      remoteUrl: sshUrl(),
    );
    await service.fetch(mirror);
    expect(
      await service.resolveRef(mirror, 'develop'),
      fixture.git(['rev-parse', 'develop']),
    );
    final calls = File(log).readAsLinesSync();
    expect(calls, hasLength(2));
    for (final call in calls) {
      expect(call, contains('-o BatchMode=yes'));
      expect(call, contains('-o StrictHostKeyChecking=accept-new'));
      expect(call, contains('git@git.example.com'));
    }
  });

  test("fails with ssh's words on a host key that changed", () async {
    expect(
      await failureOf(serviceIn('changed'), sshUrl()),
      allOf(
        contains('REMOTE HOST IDENTIFICATION HAS CHANGED'),
        contains('Host key verification failed.'),
      ),
    );
  });

  test(
    'fails with the words of GitHub and Bitbucket for a key they refuse',
    () async {
      for (final host in ['github.com', 'bitbucket.org']) {
        expect(
          await failureOf(
            serviceIn('denied', userHost: 'git@$host'),
            'git@$host:ws/app.git',
          ),
          contains('git@$host: Permission denied (publickey).'),
          reason: host,
        );
      }
    },
  );

  test('reads a file:// repository without SSH', () async {
    final service = serviceIn('denied');

    expect(await service.lsRemote(fixture.originUrl), 'develop');
    expect(File(log).existsSync(), isFalse);
  });

  test('refuses a URL that looks like an option', () {
    expect(serviceIn('new').lsRemote('--upload-pack=x'), throwsArgumentError);
    expect(serviceIn('new').lsRemote(''), throwsArgumentError);
  });
}
