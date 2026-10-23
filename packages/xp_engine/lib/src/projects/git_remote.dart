import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// A repository on any git host, as XPath reaches it without GitHub: over
/// SSH with the machine's own key, or a local `file://` repository
/// (ADR 0015).
class GitRemote extends Equatable {
  /// Creates a remote.
  const new({required this.host, required this.path, this.port});

  /// The [host] of a `file://` remote.
  static const localHost = 'local';

  /// Reads an SSH URL, scp-like (`[user@]host:path`) or `ssh://`, or a
  /// `file://` URL. `null` for anything else, such as an HTTPS URL or a
  /// plain folder. git fetches from the URL as it is given; the remote only
  /// says where it points.
  static GitRemote? parse(String text) {
    final url = text.trim();
    if (url.startsWith('file://')) {
      final path = Uri.tryParse(url)?.path;
      if (path == null || !path.startsWith('/')) return null;
      return _of(localHost, path);
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

  /// The SSH URL of the repository that the HTTPS URL [text] names, for a
  /// host other than GitHub: `https://bitbucket.org/ws/repo.git` gives
  /// `git@bitbucket.org:ws/repo.git`. `null` if [text] is not an `http(s)`
  /// URL with a path.
  ///
  /// XPath has no credentials for other hosts over HTTPS, so it offers this
  /// URL instead; the owner confirms it (ADR 0015).
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

  /// The host, in lower case, or [localHost] for a `file://` remote.
  final String host;

  /// The repository's path on [host], without a leading or trailing `/` and
  /// without `.git`. On a hosting service it is `owner/name`, or more
  /// segments for a GitLab subgroup; for a local repository it is the
  /// absolute folder without its leading `/`.
  final String path;

  /// The SSH port when it is not 22.
  final int? port;

  /// Whether the repository is a local `file://` one.
  bool get isLocal => host == localHost;

  /// `owner/name`, as projects show it: the [path].
  String get fullName => path;

  /// The remote with the user, the default port and `.git` dropped and the
  /// host in lower case, so that every spelling of one repository is the
  /// same text.
  String get normalised => isLocal
      ? 'file:///$path'
      : 'ssh://$host${port == null ? '' : ':$port'}/$path';

  /// The project's source key: `h` and the first 16 hex digits of the
  /// SHA-256 of [normalised] (ADR 0015).
  String get sourceKey =>
      'h${sha256.convert(utf8.encode(normalised)).toString().substring(0, 16)}';

  @override
  List<Object?> get props => [host, path, port];
}
