/// Who git records as the author of what XPath creates: annotated tags and,
/// later, version commits.
class GitIdentity {
  /// Creates an identity.
  const new({required this.name, required this.email});

  /// The identity used unless the engine is configured otherwise.
  static const xpath = GitIdentity(name: 'XPath', email: 'xpath@localhost');

  /// The `user.name`.
  final String name;

  /// The `user.email`.
  final String email;
}
