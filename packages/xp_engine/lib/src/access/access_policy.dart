import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// Who may do what: the one place that reads a token's kind and role to
/// decide (ADR 0017).
///
/// A permission needs the person's role to be at least its
/// [Permission.minimumRole], and the token's kind rules apply on top:
///
/// - a `runner` token belongs to no person and has no permission (its
///   routes are scoped by ADR 0011);
/// - an `mcp` token may [Permission.develop] and nothing else, so an agent
///   never decides or changes gates;
/// - only `app` and `web` tokens turn gates off ([mayLoosenGates]) or make
///   tokens ([mayCreateToken]), and only a person's `app`, `cli` and `web`
///   tokens list and revoke tokens ([mayManageTokens]);
/// - a sign-in code for the web dashboard comes from an admin, or from the
///   person's own `app` or `cli` token ([mayIssueSignInCode]);
/// - the session cookie of a browser carries a `web` token and no other
///   ([mayUseSessionCookie]), and only a `web` token signs out
///   ([maySignOut]).
abstract final class AccessPolicy {
  static const Set<DeviceTokenKind> _people = {
    DeviceTokenKind.app,
    DeviceTokenKind.cli,
    DeviceTokenKind.web,
  };

  static const Set<DeviceTokenKind> _interactive = {
    DeviceTokenKind.app,
    DeviceTokenKind.web,
  };

  /// Whether [token] has [permission].
  static bool allows(DeviceToken token, Permission permission) =>
      _kindAllows(token.kind, permission) && _roleAllows(token, permission);

  /// Every permission [token] has, in the order of [Permission.values]:
  /// what `GET /me` answers (D16).
  static List<Permission> permissionsOf(DeviceToken token) => [
    for (final permission in Permission.values)
      if (allows(token, permission)) permission,
  ];

  /// Why [token] lacks [permission], as an answer to the owner who tried to
  /// [what]; `null` if it has it.
  static String? refusal(
    DeviceToken token,
    Permission permission,
    String what,
  ) {
    if (!_kindAllows(token.kind, permission)) {
      return '${aTokenOf(token.kind)} cannot $what: only the app, '
          '`xp` or the web dashboard do.';
    }
    if (!_roleAllows(token, permission)) {
      return 'A ${token.role?.name ?? 'token without a person'} cannot '
          '$what: it takes the ${permission.minimumRole.name} role or higher.';
    }
    return null;
  }

  /// Whether [token] may turn a gate off: an admin's `app` or `web` token.
  static bool mayLoosenGates(DeviceToken token) =>
      _interactive.contains(token.kind) && allows(token, Permission.administer);

  /// The kinds of token a person makes from the app or the dashboard
  /// (D17): an `app` or a `runner` token comes from `xpd token create` and
  /// pairing only.
  static const Set<DeviceTokenKind> mintableKinds = {
    DeviceTokenKind.cli,
    DeviceTokenKind.mcp,
  };

  /// Whether [token] may make a [kind] token for its own person: an `app`
  /// or `web` token of any role, and only a kind of [mintableKinds].
  static bool mayCreateToken(DeviceToken token, DeviceTokenKind kind) =>
      _interactive.contains(token.kind) &&
      token.role != null &&
      mintableKinds.contains(kind);

  /// Whether [token] may list and revoke tokens (D17): a person's `app`,
  /// `cli` or `web` token. An agent's `mcp` token never may, so it cannot
  /// sign the app or a browser out.
  static bool mayManageTokens(DeviceToken token) =>
      _people.contains(token.kind) && token.role != null;

  /// Whether a browser's session cookie may carry [token] (ADR 0018, D3a):
  /// only a `web` token, the one signing in makes.
  static bool mayUseSessionCookie(DeviceToken token) =>
      token.kind == DeviceTokenKind.web;

  /// Whether [token] may sign itself out with `DELETE /session`: only a
  /// browser's `web` token. Other tokens are revoked with
  /// `DELETE /tokens/{id}`.
  static bool maySignOut(DeviceToken token) =>
      token.kind == DeviceTokenKind.web;

  /// Whether [token] is a runner's (ADR 0011): it connects as a runner and
  /// reaches the runner routes and nothing else.
  static bool isRunner(DeviceToken token) =>
      token.kind == DeviceTokenKind.runner;

  /// Whether a token of [kind] belongs to a person: every kind but a
  /// runner's, which is a machine's (D6).
  static bool hasPerson(DeviceTokenKind kind) => kind != DeviceTokenKind.runner;

  /// Whether [token] may issue a sign-in code for the person [personId]
  /// (D9): an admin may for anyone, and a person's own `app` or `cli` token
  /// for them, so the app and `xp dashboard` open the dashboard. An agent's
  /// token never may, and neither may a browser for itself.
  static bool mayIssueSignInCode(DeviceToken token, String personId) =>
      allows(token, Permission.administer) ||
      (_selfSignIn.contains(token.kind) &&
          token.role != null &&
          token.personId == personId);

  static const Set<DeviceTokenKind> _selfSignIn = {
    DeviceTokenKind.app,
    DeviceTokenKind.cli,
  };

  /// A token of [kind], with its article, to begin a refusal: "An mcp
  /// token", "A cli token".
  static String aTokenOf(DeviceTokenKind kind) => switch (kind) {
    DeviceTokenKind.app || DeviceTokenKind.mcp => 'An ${kind.name} token',
    DeviceTokenKind.cli ||
    DeviceTokenKind.runner ||
    DeviceTokenKind.web => 'A ${kind.name} token',
  };

  static bool _kindAllows(DeviceTokenKind kind, Permission permission) =>
      _people.contains(kind) ||
      (kind == DeviceTokenKind.mcp && permission == Permission.develop);

  static bool _roleAllows(DeviceToken token, Permission permission) =>
      token.role?.isAtLeast(permission.minimumRole) ?? false;
}
