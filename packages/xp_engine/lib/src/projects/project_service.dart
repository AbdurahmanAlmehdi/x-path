import 'dart:async';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/git/git_access.dart';
import 'package:xp_engine/src/git/git_exceptions.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/git/github_client.dart';
import 'package:xp_engine/src/git/github_exceptions.dart';
import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/projects/apply_edits.dart';
import 'package:xp_engine/src/projects/git_remote.dart';
import 'package:xp_engine/src/projects/github_remote.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_record.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/scan/project_scanner.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';

/// Opens a read-only [ScanSource] over the directory [directory] of the
/// engine's machine.
typedef ScanSourceFactory = ScanSource Function(String directory);

/// Adds, scans, edits and removes projects (D-04, D-05).
///
/// A project is a repository keyed by its source key (ADR 0015). Adding by
/// path reads the `origin` of the folder, sets up the engine's own mirror and
/// scans the folder: the folder only identifies the repository and seeds the
/// scan. Adding by remote scans a fresh worktree of the mirror instead.
/// Nothing is ever written to the folder.
///
/// A GitHub repository is asked of GitHub and keyed by its id. Any other one
/// is reached over SSH or `file://` with the engine's own access: `git
/// ls-remote` proves it and reads the default branch, and no GitHub call is
/// made.
///
/// Operations that change projects run one at a time.
class ProjectService {
  /// Creates the service.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._repository,
    required this._github,
    required this._git,
    required this._scanner,
    required this._sources,
    required this._runner,
    required this._events,
    required this._clock,
    Random? random,
    this.gitTimeout = const Duration(seconds: 30),
  }) : _random = random ?? Random.secure();

  /// How long `git remote get-url` may take.
  final Duration gitTimeout;

  final ProjectRepository _repository;
  final GitHubClient _github;
  final GitService _git;
  final ProjectScanner _scanner;
  final ScanSourceFactory _sources;
  final ProcessRunner _runner;
  final EventLog _events;
  final Clock _clock;
  final Random _random;
  Future<void> _tail = Future.value();

  /// Every project, oldest first.
  Future<List<Project>> list() async => [
    for (final record in await _repository.list()) record.toProject(),
  ];

  /// The project [id].
  ///
  /// Throws a [ProjectNotFoundException] if there is none.
  Future<Project> get(String id) async => (await _require(id)).toProject();

  /// Adds the repository that [request] names and scans it.
  ///
  /// Throws a [ProjectInvalidException] unless exactly one of path and remote
  /// is given and it names a repository XPath can reach, a
  /// [ProjectSshUrlRequiredException] for an HTTPS origin on a host other
  /// than GitHub without the confirmed SSH URL, a [ProjectExistsException]
  /// if the repository is a project already, a `GitHubException` if GitHub
  /// refuses and a `GitException` if the repository cannot be read (with
  /// what to do on its host) or the mirror cannot be filled.
  Future<Project> add(AddProjectRequest request) => _exclusive(() async {
    final path = request.path;
    final remote = request.remote;
    if ((path == null) == (remote == null)) {
      throw const ProjectInvalidException(
        'Give exactly one of "path" and "remote".',
      );
    }
    if (path != null) return await _addFolder(path, request.sshUrl);
    return await _addRemote(remote!, localPath: null, sshUrl: request.sshUrl);
  });

  /// Scans the project [id] again and keeps the owner's edits.
  ///
  /// The folder it was added from is scanned if it still exists, else a fresh
  /// worktree of the mirror. GitHub is asked for the repository first, so a
  /// rename or a new default branch is followed (D-05); if GitHub cannot be
  /// reached the stored values stay.
  Future<Project> scan(String id) => _exclusive(() async {
    var record = await _require(id);
    if (record.githubRepoId case final githubRepoId?) {
      try {
        final repo = await _github.getRepoById(githubRepoId);
        record = record.copyWith(
          fullName: repo.fullName,
          remote: repo.cloneUrl,
          githubDefaultBranch: repo.defaultBranch,
        );
      } on GitHubException {
        // Offline or unauthorized: scan with what is stored.
      } on SecretStoreException {
        // Secrets are locked: same.
      }
    }
    final mirror = await _git.ensureMirror(
      key: record.sourceKey,
      remoteUrl: record.remote,
    );
    final localPath = record.localPath;
    final result = localPath != null && await _sources(localPath).exists('')
        ? await _scanner.scan(_sources(localPath))
        : await _scanMirror(mirror, record.githubDefaultBranch, record.id);
    record = record.copyWith(
      scan: _withDefaultBranch(result.profile, record.githubDefaultBranch),
      findings: result.findings,
      scannedAt: _clock.now(),
    );
    await _repository.update(record);
    _scanned(record);
    return record.toProject();
  });

  /// Applies the owner's corrections [patch] to the profile of the project
  /// [id]. They survive rescans.
  ///
  /// Throws a [ProjectInvalidException] for an edit of an app or flavor the
  /// profile does not have, or a value that is not valid.
  Future<Project> update(String id, ProfileEdits patch) => _exclusive(() async {
    final record = await _require(id);
    final valid = validateEdits(record.profile, patch);
    final updated = record.copyWith(edits: record.edits.merge(valid));
    await _repository.update(updated);
    _events.append(ProjectEdited(projectId: id));
    return updated.toProject();
  });

  /// Removes the project [id]. The mirror stays on disk and the folder is
  /// never touched.
  ///
  /// Throws a [ProjectNotFoundException] if there is none.
  Future<void> remove(String id) => _exclusive(() async {
    if (!await _repository.remove(id)) throw ProjectNotFoundException(id);
    _events.append(ProjectRemoved(projectId: id));
  });

  Future<ProjectRecord> _require(String id) async =>
      await _repository.get(id) ?? (throw ProjectNotFoundException(id));

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Project> _addFolder(String path, String? sshUrl) async {
    if (!path.startsWith('/')) {
      throw ProjectInvalidException('"$path" is not an absolute path.');
    }
    if (!await _sources(path).exists('')) {
      throw ProjectInvalidException('"$path" is not a folder.');
    }
    final origin = await _originOf(path);
    // A clone of a local repository names it by its folder.
    final url = origin.startsWith('/') ? Uri.file(origin).toString() : origin;
    return await _addRemote(url, localPath: path, sshUrl: sshUrl);
  }

  /// Adds the repository at [url]: a GitHub one through GitHub, any other
  /// over SSH or `file://`. An HTTPS [url] on another host is read at
  /// [sshUrl], the SSH URL the owner confirmed for the folder [localPath].
  Future<Project> _addRemote(
    String url, {
    required String? localPath,
    required String? sshUrl,
  }) async {
    final github = GitHubRemote.parse(url);
    final remote = github == null ? GitRemote.parse(url) : null;
    final derived = github == null && remote == null
        ? GitRemote.sshUrlFor(url)
        : null;
    if (sshUrl != null && (localPath == null || derived == null)) {
      throw const ProjectInvalidException(
        '"sshUrl" only goes with a "path" whose origin is an HTTPS URL on a '
        'host other than GitHub; leave it out.',
      );
    }
    if (github != null) return await _register(github, localPath: localPath);
    if (remote != null) {
      return await _registerOther(
        _notOnGitHub(remote, url),
        url.trim(),
        localPath: localPath,
      );
    }
    if (derived == null) {
      throw ProjectInvalidException(
        '"$url" is not a repository XPath can reach. Give a GitHub '
        'repository, an SSH URL (git@host:path or ssh://) or a file:// URL.',
      );
    }
    final offered = _notOnGitHub(GitRemote.parse(derived)!, url);
    if (sshUrl == null) {
      throw ProjectSshUrlRequiredException(host: offered.host, sshUrl: derived);
    }
    final confirmed = GitRemote.parse(sshUrl);
    if (confirmed == null || confirmed.sourceKey != offered.sourceKey) {
      throw ProjectInvalidException(
        '"$sshUrl" is not the SSH URL of $url. Use $derived.',
      );
    }
    return await _registerOther(confirmed, sshUrl.trim(), localPath: localPath);
  }

  /// [remote], unless it is on GitHub: a GitHub repository is read with the
  /// GitHub token and keyed by its id, so it must be named in a form
  /// [GitHubRemote.parse] reads, never by an SSH or derived URL.
  GitRemote _notOnGitHub(GitRemote remote, String url) {
    if (remote.host != Project.githubHost) return remote;
    throw ProjectInvalidException(
      '"$url" is on GitHub, but not in a form XPath reads. Give the '
      'repository as owner/name.',
    );
  }

  /// The URL of `origin` in the clone at [path]. Only reads its config.
  Future<String> _originOf(String path) async {
    final ProcessOutput output;
    try {
      output = await _runner.run(
        'git',
        ['-C', path, 'remote', 'get-url', 'origin'],
        environment: {'GIT_OPTIONAL_LOCKS': '0', 'GIT_TERMINAL_PROMPT': '0'},
        timeout: gitTimeout,
      );
    } on ProcessStartException catch (error) {
      throw ProjectInvalidException('Cannot run git: ${error.message}');
    } on TimeoutException {
      throw ProjectInvalidException('git did not answer for $path.');
    }
    final url = output.stdout.trim();
    if (output.exitCode != 0 || url.isEmpty) {
      throw ProjectInvalidException('$path has no git remote called origin.');
    }
    return url;
  }

  Future<Project> _register(
    GitHubRemote remote, {
    required String? localPath,
  }) async {
    final repo = await _github.getRepo(remote.owner, remote.name);
    await _refuseExisting('${repo.id}');
    return await _finishAdding(
      host: Project.githubHost,
      sourceKey: '${repo.id}',
      githubRepoId: repo.id,
      fullName: repo.fullName,
      url: repo.cloneUrl,
      branch: repo.defaultBranch,
      localPath: localPath,
    );
  }

  /// Registers the repository [remote] on a host other than GitHub, fetched
  /// from [url] with the engine's own SSH access (ADR 0015). `git ls-remote`
  /// proves the access and reads the default branch.
  Future<Project> _registerOther(
    GitRemote remote,
    String url, {
    required String? localPath,
  }) async {
    final key = remote.sourceKey;
    await _refuseExisting(key);
    final String branch;
    try {
      branch = await _git.lsRemote(url);
    } on GitException catch (error) {
      throw GitException(
        explainGitAccess(
              error.message,
              url: url,
              reader: GitAccessReader.engine,
            ) ??
            'XPath cannot read $url: ${error.message}',
      );
    }
    return await _finishAdding(
      host: remote.host,
      sourceKey: key,
      fullName: remote.path,
      url: url,
      branch: branch,
      localPath: localPath,
    );
  }

  Future<void> _refuseExisting(String sourceKey) async {
    final existing = await _repository.findBySourceKey(sourceKey);
    if (existing != null) {
      throw ProjectExistsException(existing.id, existing.fullName);
    }
  }

  /// Sets up the mirror of a repository whose identity is resolved, scans it
  /// (the folder [localPath], else the [branch] of the mirror) and stores
  /// the project.
  Future<Project> _finishAdding({
    required String host,
    required String sourceKey,
    required String fullName,
    required String url,
    required String branch,
    required String? localPath,
    int? githubRepoId,
  }) async {
    final id = 'prj_${_hex(8)}';
    final mirror = await _git.ensureMirror(key: sourceKey, remoteUrl: url);
    final result = localPath != null
        ? await _scanner.scan(_sources(localPath))
        : await _scanMirror(mirror, branch, id);
    final record = ProjectRecord(
      id: id,
      host: host,
      sourceKey: sourceKey,
      githubRepoId: githubRepoId,
      fullName: fullName,
      remote: url,
      githubDefaultBranch: branch,
      localPath: localPath,
      scan: _withDefaultBranch(result.profile, branch),
      findings: result.findings,
      scannedAt: _clock.now(),
    );
    await _repository.add(record);
    _events.append(ProjectAdded(projectId: id, fullName: fullName));
    _scanned(record);
    return record.toProject();
  }

  /// Scans the default branch of the mirror in a worktree of its own.
  Future<ScanResult> _scanMirror(
    GitMirror mirror,
    String branch,
    String id,
  ) async {
    await _git.fetch(mirror);
    final sha = await _git.resolveRef(mirror, branch);
    final worktree = await _git.createWorktree(
      mirror,
      name: 'scan-$id',
      sha: sha,
    );
    try {
      return await _scanner.scan(_sources(worktree.path));
    } finally {
      await _git.removeWorktree(worktree);
    }
  }

  ProjectProfile _withDefaultBranch(ProjectProfile profile, String branch) =>
      profile.copyWith(branches: profile.branches.withDefaultBranch(branch));

  void _scanned(ProjectRecord record) => _events.append(
    ProjectScanned(
      projectId: record.id,
      errors: _count(record, FindingSeverity.error),
      warnings: _count(record, FindingSeverity.warning),
    ),
  );

  int _count(ProjectRecord record, FindingSeverity severity) =>
      record.findings.where((finding) => finding.severity == severity).length;

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
