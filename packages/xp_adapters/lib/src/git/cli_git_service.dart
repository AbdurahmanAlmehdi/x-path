import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/src/git/git_identity.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [GitService] over the `git` command line.
///
/// Layout under the data directory: the mirror of the project with source key
/// `K` (a GitHub repository id, or `h` and 16 hex digits, ADR 0015) is
/// `mirrors/K.git`, the worktree `W` of that mirror is `worktrees/K/W`.
///
/// Every command runs with the system and global git configuration switched
/// off, so nothing in the owner's `~/.gitconfig` (signing, hooks, URL
/// rewrites, credential helpers) changes what XPath does, and with terminal
/// prompts disabled, so a missing credential fails instead of hanging.
///
/// The GitHub token (`github.token` in the [SecretStore]) reaches git only for
/// `https://github.com` and only through the environment: the credential
/// helper is a shell snippet that reads `XPATH_GIT_TOKEN`, so the token is in
/// no argument, no URL and no config file. Any other host is reached over SSH
/// with the engine user's own key: commands that use the network run with
/// [sshCommand], so SSH never prompts and accepts a host key it has not seen
/// yet, but not a changed one (ADR 0015).
class CliGitService implements GitService {
  /// Creates the service.
  ///
  /// [timeout] bounds each git command; a command that takes longer is killed.
  new({
    required this._runner,
    required this._secrets,
    required this._dataDir,
    this.identity = GitIdentity.xpath,
    this.gitExecutable = 'git',
    this.timeout = const Duration(minutes: 10),
  });

  /// The author and committer of tags.
  final GitIdentity identity;

  /// The program to run.
  final String gitExecutable;

  /// How long one git command may take.
  final Duration timeout;

  final ProcessRunner _runner;
  final SecretStore _secrets;
  final String _dataDir;

  static const _tokenVariable = 'XPATH_GIT_TOKEN';

  /// The `GIT_SSH_COMMAND` of every git command that uses the network: no
  /// prompt for a password or passphrase, a bounded connect, and a host key
  /// that is recorded the first time and must not change after (Q6 of the
  /// runner plan). The runner's checkout uses the same command.
  static const sshCommand =
      'ssh -o BatchMode=yes -o ConnectTimeout=30 '
      '-o StrictHostKeyChecking=accept-new';

  // Answers git's `get` request for credentials with the token in the
  // environment; ignores `store` and `erase`.
  static const _credentialHelper =
      r'!f() { test "$1" = get || exit 0; '
      r'echo username=x-access-token; echo "password=$XPATH_GIT_TOKEN"; }; f';

  /// Where the worktree [name] of [mirror] is under the data directory
  /// [dataDir]: `worktrees/<mirror key>/<name>`.
  static String worktreePath(String dataDir, GitMirror mirror, String name) =>
      p.join(dataDir, 'worktrees', mirror.key, name);

  static final _fullSha = RegExp(r'^[0-9a-f]{40}$');
  static final _abbreviatedSha = RegExp(r'^[0-9a-fA-F]{4,40}$');
  static final _worktreeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  // `src:dst`, both full refs. A leading `+` (force) cannot match; a `+` inside
  // a name is fine, tags look like `v1.2.3+45`.
  static final _refspec = RegExp(
    r'^refs/[^\s:*?\[\\^~\x00-\x1f\x7f]+:refs/[^\s:*?\[\\^~\x00-\x1f\x7f]+$',
  );

  String get _mirrorsDir => p.join(_dataDir, 'mirrors');

  @override
  Future<GitMirror> ensureMirror({
    required String key,
    required String remoteUrl,
  }) async {
    if (!GitMirror.keyPattern.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'is not a source key');
    }
    if (remoteUrl.isEmpty || remoteUrl.startsWith('-')) {
      throw ArgumentError.value(remoteUrl, 'remoteUrl', 'is not a URL');
    }
    final path = p.join(_mirrorsDir, '$key.git');
    final mirror = GitMirror(key: key, path: path);
    if (!File(p.join(path, 'HEAD')).existsSync()) {
      Directory(_mirrorsDir).createSync(recursive: true);
      await _ok('init', [
        '-c',
        'init.defaultBranch=main',
        'init',
        '--bare',
        '--quiet',
        path,
      ], cwd: _mirrorsDir);
    }
    final current = await _git(['remote', 'get-url', 'origin'], cwd: path);
    if (current.exitCode != 0) {
      await _ok('remote', ['remote', 'add', 'origin', remoteUrl], cwd: path);
    } else if (current.stdout.trim() != remoteUrl) {
      await _ok('remote', [
        'remote',
        'set-url',
        'origin',
        remoteUrl,
      ], cwd: path);
    }
    return mirror;
  }

  @override
  Future<String> lsRemote(String url) async {
    if (url.isEmpty || url.startsWith('-')) {
      throw ArgumentError.value(url, 'url', 'is not a URL');
    }
    final output = await _git([
      'ls-remote',
      '--symref',
      url,
      'HEAD',
    ], network: true);
    if (output.exitCode != 0) throw _failure('ls-remote', output);
    final head = _symbolicHead.firstMatch(output.stdout);
    if (head == null) {
      throw GitException('$url has no branch yet: push one, then try again.');
    }
    return head.group(1)!;
  }

  // `ref: refs/heads/main<TAB>HEAD`, the first line of `ls-remote --symref`.
  static final _symbolicHead = RegExp(
    r'^ref: refs/heads/(\S+)\tHEAD$',
    multiLine: true,
  );

  /// Fetches `refs/heads/*` into `refs/remotes/origin/*` and `refs/tags/*` into
  /// itself, both forced and pruned, so the mirror shows what the remote has.
  ///
  /// A tag created in the mirror and not pushed yet is pruned by the next
  /// fetch; creating it again on the same commit is a no-op for the caller.
  @override
  Future<void> fetch(GitMirror mirror) => _ok(
    'fetch',
    [
      'fetch',
      '--prune',
      '--no-tags',
      'origin',
      '+refs/heads/*:refs/remotes/origin/*',
      '+refs/tags/*:refs/tags/*',
    ],
    cwd: mirror.path,
    network: true,
  );

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async {
    final candidates = [
      if (_fullSha.hasMatch(ref)) ref,
      'refs/heads/$ref',
      'refs/remotes/origin/$ref',
      'refs/tags/$ref',
      if (!_fullSha.hasMatch(ref) && _abbreviatedSha.hasMatch(ref)) ref,
    ];
    for (final candidate in candidates) {
      final sha = await _commitOf(mirror, candidate);
      if (sha != null) return sha;
    }
    throw GitRefNotFoundException(ref);
  }

  @override
  Future<List<GitTagInfo>> listTags(GitMirror mirror) async {
    final output = await _git([
      'for-each-ref',
      // The second object is set only for an annotated tag: the commit it
      // names.
      '--format=%(refname:strip=2)%09%(objectname)%09%(*objectname)',
      'refs/tags',
    ], cwd: mirror.path);
    if (output.exitCode != 0) throw _failure('for-each-ref', output);
    return [
      for (final line in const LineSplitter().convert(output.stdout))
        if (line.isNotEmpty) _tagOf(line),
    ];
  }

  GitTagInfo _tagOf(String line) {
    final fields = line.split('\t');
    final peeled = fields[2];
    return GitTagInfo(
      name: fields[0],
      commit: peeled.isEmpty ? fields[1] : peeled,
    );
  }

  @override
  Future<List<String>> changedFiles(
    GitMirror mirror, {
    required String from,
    required String to,
  }) async {
    final before = await resolveRef(mirror, from);
    final after = await resolveRef(mirror, to);
    final output = await _git([
      'diff',
      '--name-only',
      '-z',
      '--no-renames',
      before,
      after,
    ], cwd: mirror.path);
    if (output.exitCode != 0) throw _failure('diff', output);
    return _nulSeparated(output.stdout)..sort();
  }

  @override
  Future<List<GitCommit>> commitsBetween(
    GitMirror mirror, {
    required String to,
    String? from,
    int limit = 500,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'is below 1');
    final end = await resolveRef(mirror, to);
    final start = from == null ? null : await resolveRef(mirror, from);
    final output = await _git([
      'log',
      '--no-merges',
      '--max-count=$limit',
      // NUL between commits; the unit separator between the fields.
      '-z',
      '--format=%H%x1f%s%x1f%b',
      if (start == null) end else '$start..$end',
    ], cwd: mirror.path);
    if (output.exitCode != 0) throw _failure('log', output);
    return [
      for (final record in _nulSeparated(output.stdout)) _commitFrom(record),
    ];
  }

  GitCommit _commitFrom(String record) {
    final fields = record.split('\x1f');
    return GitCommit(
      sha: fields[0].trim(),
      subject: fields[1],
      body: fields[2].trim(),
    );
  }

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    if (!_worktreeName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'is not a safe directory name');
    }
    final full = await resolveRef(mirror, sha);
    final path = worktreePath(_dataDir, mirror, name);
    await _discardWorktree(mirror, path);
    Directory(p.dirname(path)).createSync(recursive: true);
    await _ok('worktree', [
      'worktree',
      'add',
      '--detach',
      path,
      full,
    ], cwd: mirror.path);
    return GitWorktree(mirror: mirror, path: path, sha: full);
  }

  @override
  Future<void> removeWorktree(GitWorktree worktree) =>
      _discardWorktree(worktree.mirror, worktree.path);

  @override
  Future<GitWorktreeStatus> status(GitWorktree worktree) async {
    final head = await _head(worktree);
    final output = await _git([
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--no-renames',
    ], cwd: worktree.path);
    if (output.exitCode != 0) throw _failure('status', output);
    final changed = <String>[];
    final untracked = <String>[];
    for (final entry in _nulSeparated(output.stdout)) {
      // `XY path`: two status letters, a space, the path.
      final path = entry.substring(3);
      (entry.startsWith('??') ? untracked : changed).add(path);
    }
    return GitWorktreeStatus(
      headSha: head,
      changed: changed..sort(),
      untracked: untracked..sort(),
    );
  }

  @override
  Future<GitCommitResult> commit(
    GitWorktree worktree, {
    required String message,
    required List<String> paths,
  }) async {
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'is blank');
    }
    if (paths.isEmpty) {
      throw ArgumentError.value(paths, 'paths', 'is empty');
    }
    for (final path in paths) {
      if (path.isEmpty ||
          path.startsWith('-') ||
          path.startsWith('/') ||
          path.split('/').contains('..')) {
        throw ArgumentError.value(path, 'paths', 'is not a safe path');
      }
    }
    final cwd = worktree.path;
    await _ok('add', ['add', '--', ...paths], cwd: cwd);
    // Exit code 1 means the staged paths differ from the head.
    final diff = await _git([
      'diff',
      '--cached',
      '--quiet',
      '--',
      ...paths,
    ], cwd: cwd);
    if (diff.exitCode != 0 && diff.exitCode != 1) {
      throw _failure('diff', diff);
    }
    if (diff.exitCode == 0) {
      return GitCommitResult(
        sha: await _head(worktree),
        tree: await _revParse(cwd, 'HEAD^{tree}'),
        created: false,
      );
    }
    await _ok('commit', [
      'commit',
      '--quiet',
      '--no-verify',
      '-m',
      message,
      '--',
      ...paths,
    ], cwd: cwd);
    return GitCommitResult(
      sha: await _head(worktree),
      tree: await _revParse(cwd, 'HEAD^{tree}'),
      created: true,
    );
  }

  @override
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  }) async {
    await _checkRefName('refs/tags/$name', name);
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'is blank');
    }
    final full = await resolveRef(mirror, sha);
    final existing = await _commitOf(mirror, 'refs/tags/$name');
    if (existing != null) {
      if (existing == full) return TagOutcome.reused;
      throw GitTagConflictException(
        tag: name,
        existingSha: existing,
        requestedSha: full,
      );
    }
    await _ok('tag', [
      'tag',
      '-a',
      '-m',
      message,
      name,
      full,
    ], cwd: mirror.path);
    return TagOutcome.created;
  }

  @override
  Future<BranchOutcome> upsertBranch(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    await _checkRefName('refs/heads/$name', name);
    final full = await resolveRef(mirror, sha);
    final local = await _commitOf(mirror, 'refs/heads/$name');
    if (local == full) return BranchOutcome.unchanged;
    final tip = local ?? await _commitOf(mirror, 'refs/remotes/origin/$name');
    if (tip != null && !await _isAncestor(mirror, tip, full)) {
      throw GitBranchConflictException(
        branch: name,
        currentSha: tip,
        requestedSha: full,
      );
    }
    // The old value makes the update atomic: an empty one means "must not
    // exist yet".
    await _ok('update-ref', [
      'update-ref',
      'refs/heads/$name',
      full,
      local ?? '',
    ], cwd: mirror.path);
    return local == null ? BranchOutcome.created : BranchOutcome.updated;
  }

  @override
  Future<void> push(GitMirror mirror, {required List<String> refspecs}) async {
    if (refspecs.isEmpty) {
      throw ArgumentError.value(refspecs, 'refspecs', 'is empty');
    }
    for (final refspec in refspecs) {
      if (!_refspec.hasMatch(refspec)) {
        throw ArgumentError.value(
          refspec,
          'refspecs',
          'is not a plain refs/...:refs/... refspec',
        );
      }
    }
    final output = await _git(
      ['push', 'origin', ...refspecs],
      cwd: mirror.path,
      network: true,
    );
    if (output.exitCode == 0) return;
    final stderr = output.stderr.trim();
    final rejected =
        stderr.contains('rejected') ||
        stderr.contains('non-fast-forward') ||
        stderr.contains('already exists');
    final message = 'git push failed (exit ${output.exitCode}): $stderr';
    throw rejected ? GitPushRejectedException(message) : GitException(message);
  }

  Future<String> _head(GitWorktree worktree) =>
      _revParse(worktree.path, 'HEAD');

  Future<String> _revParse(String cwd, String ref) async {
    final output = await _git(['rev-parse', '--verify', ref], cwd: cwd);
    if (output.exitCode != 0) throw _failure('rev-parse', output);
    return output.stdout.trim();
  }

  /// The non-empty entries of NUL-separated [text].
  List<String> _nulSeparated(String text) => [
    for (final entry in text.split('\x00'))
      if (entry.isNotEmpty) entry,
  ];

  /// Forgets the worktree at [path] and deletes its directory, whatever state
  /// it is in.
  Future<void> _discardWorktree(GitMirror mirror, String path) async {
    if (Directory(mirror.path).existsSync()) {
      await _git(['worktree', 'remove', '--force', path], cwd: mirror.path);
    }
    final directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    if (Directory(mirror.path).existsSync()) {
      await _git(['worktree', 'prune'], cwd: mirror.path);
    }
  }

  /// Fails with an [ArgumentError] unless [fullRef] is a valid ref and [name]
  /// cannot be mistaken for an option.
  Future<void> _checkRefName(String fullRef, String name) async {
    final valid =
        !name.startsWith('-') &&
        (await _git(['check-ref-format', fullRef])).exitCode == 0;
    if (!valid) throw ArgumentError.value(name, 'name', 'is not a valid name');
  }

  /// The commit that [ref] points at, or `null` if there is none.
  Future<String?> _commitOf(GitMirror mirror, String ref) async {
    final output = await _git([
      'rev-parse',
      '--verify',
      '--quiet',
      '$ref^{commit}',
    ], cwd: mirror.path);
    if (output.exitCode == 0) return output.stdout.trim();
    if (output.exitCode == 1) return null;
    throw _failure('rev-parse', output);
  }

  Future<bool> _isAncestor(
    GitMirror mirror,
    String ancestor,
    String descendant,
  ) async {
    final output = await _git([
      'merge-base',
      '--is-ancestor',
      ancestor,
      descendant,
    ], cwd: mirror.path);
    if (output.exitCode == 0) return true;
    if (output.exitCode == 1) return false;
    throw _failure('merge-base', output);
  }

  Future<void> _ok(
    String what,
    List<String> arguments, {
    required String cwd,
    bool network = false,
  }) async {
    final output = await _git(arguments, cwd: cwd, network: network);
    if (output.exitCode != 0) throw _failure(what, output);
  }

  GitException _failure(String what, ProcessOutput output) => GitException(
    'git $what failed (exit ${output.exitCode}): ${output.stderr.trim()}',
  );

  Future<ProcessOutput> _git(
    List<String> arguments, {
    String? cwd,
    bool network = false,
  }) async {
    final environment = {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_TERMINAL_PROMPT': '0',
      // Git's messages are matched by text; keep them in English.
      'LC_ALL': 'C',
    };
    final config = [
      'user.name=${identity.name}',
      'user.email=${identity.email}',
    ];
    if (network) {
      environment['GIT_SSH_COMMAND'] = sshCommand;
      final token = await _secrets.read(githubTokenSecretKey);
      if (token != null) {
        environment[_tokenVariable] = token;
        config
          ..add('credential.helper=')
          ..add('credential.https://github.com.helper=$_credentialHelper');
      }
    }
    try {
      return await _runner.run(
        gitExecutable,
        [
          for (final entry in config) ...['-c', entry],
          ...arguments,
        ],
        workingDirectory: cwd,
        environment: environment,
        timeout: timeout,
      );
    } on TimeoutException {
      throw GitException('git ${arguments.first} timed out after $timeout.');
    } on ProcessStartException catch (error) {
      throw GitException('Cannot run git: ${error.message}');
    }
  }
}
