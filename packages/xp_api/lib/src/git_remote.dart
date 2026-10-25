import 'package:equatable/equatable.dart';
import 'package:xp_api/src/project.dart';

/// A repository on any git host, as XPath reaches it without GitHub: over
/// SSH with the machine's own key, or a local `file://` repository
/// (ADR 0015). Only parsing: the engine derives the source key from
/// [normalised].
class GitRemote extends Equatable {
  /// Creates a remote.
  const new({required this.host, required this.path, this.port});

  /// Reads an SSH URL, scp-like (`[user@]host:path`) or `ssh://`, or a
  /// `file://` URL. `null` for anything else, such as an HTTPS URL or a
  /// plain folder. git fetches from the URL as it is given; the remote only
  /// says where it points.
  static GitRemote? parse(String text) {
    final url = text.trim();
    if (url.startsWith('file://')) {
      final path = Uri.tryParse(url)?.path;
      if (path == null || !path.startsWith('/')) return null;
      return _of(Project.localHost, path);
    }
    if (url.startsWith('ssh://')) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) return null;
      return _of(uri.host, uri.path, port: uri.hasPort ? uri.port : null);
    }
    if (url.contains('://')) return null;
    if (_scpLike.firstMatch(url) case final match?) {
      return _of(match.group(1)!, match.group(2)!);
    }
    return null;
  }

  /// The SSH URL of the repository that the HTTPS URL [text] names:
  /// `https://bitbucket.org/ws/repo.git` gives
  /// `git@bitbucket.org:ws/repo.git`. `null` if [text] is not an `http(s)`
  /// URL with a path.
  ///
  /// XPath has no credentials for hosts other than GitHub over HTTPS, so it
  /// offers this URL instead; the owner confirms it (ADR 0015).
  static String? sshUrlFor(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    final remote = _of(uri.host, uri.path);
    if (remote == null) return null;
    return 'git@${remote.host}:${remote.path}.git';
  }

  // `[user@]host:path`, where the host has no `/` (git's own rule).
  static final _scpLike = RegExp(r'^(?:[^@/\s:]+@)?([^@/\s:]+):(.+)$');

  static GitRemote? _of(String host, String path, {int? port}) {
    final trimmed = path
        .replaceFirst(RegExp('^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '')
        .replaceFirst(RegExp(r'\.git$'), '');
    final segments = trimmed.split('/');
    if (host.isEmpty ||
        trimmed.isEmpty ||
        segments.any((segment) => segment.isEmpty || segment == '..')) {
      return null;
    }
    return GitRemote(
      host: host.toLowerCase(),
      path: trimmed,
      port: port == 22 ? null : port,
    );
  }

  /// The host, in lower case, or [Project.localHost] for a `file://` remote.
  final String host;

  /// The repository's path on [host], without a leading or trailing `/` and
  /// without `.git`: `owner/name` on a hosting service, or more segments for
  /// a GitLab subgroup. A project shows it as its `fullName`. For a local
  /// repository it is the absolute folder without its leading `/`.
  final String path;

  /// The SSH port when it is not 22.
  final int? port;

  /// The remote with the user, the default port and `.git` dropped and the
  /// host in lower case, so that every spelling of one repository is the
  /// same text.
  String get normalised => host == Project.localHost
      ? 'file:///$path'
      : 'ssh://$host${port == null ? '' : ':$port'}/$path';

  @override
  List<Object?> get props => [host, path, port];
}
