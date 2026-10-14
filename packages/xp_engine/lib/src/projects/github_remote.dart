import 'package:equatable/equatable.dart';

/// A GitHub repository as a remote spells it.
class GitHubRemote extends Equatable {
  /// Creates a remote for `owner/name`.
  const new({required this.owner, required this.name});

  /// Reads `owner/name`, `github.com/owner/name`, or an HTTPS, SSH or `git@`
  /// URL of a GitHub repository, with or without `.git`. `null` for anything
  /// else, such as a repository on another host.
  static GitHubRemote? parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final owner = match.group(1)!;
    final name = match.group(2)!;
    if (_dots.hasMatch(owner) || _dots.hasMatch(name)) return null;
    return GitHubRemote(owner: owner, name: name);
  }

  static final _pattern = RegExp(
    r'^(?:(?:https?|ssh|git)://(?:[^@/\s]+@)?github\.com/|git@github\.com:'
    r'|github\.com/)?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$',
    caseSensitive: false,
  );
  static final _dots = RegExp(r'^\.+$');

  /// The account or organization.
  final String owner;

  /// The repository name, without `.git`.
  final String name;

  /// `owner/name`.
  String get fullName => '$owner/$name';

  /// The SSH URL a machine with its own SSH key fetches the repository from.
  String get sshUrl => 'git@github.com:$owner/$name.git';

  @override
  List<Object?> get props => [owner, name];
}
