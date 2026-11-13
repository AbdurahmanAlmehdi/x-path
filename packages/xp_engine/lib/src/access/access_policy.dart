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
///   tokens ([mayCreateTokens]).
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
      return 'A ${token.kind.name} token cannot $what: only the app or `xp` '
          'do.';
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

  /// Whether [token] may make tokens for its own person: an `app` or `web`
  /// token of any role.
  static bool mayCreateTokens(DeviceToken token) =>
      _interactive.contains(token.kind) && token.role != null;

  static bool _kindAllows(DeviceTokenKind kind, Permission permission) =>
      _people.contains(kind) ||
      (kind == DeviceTokenKind.mcp && permission == Permission.develop);

  static bool _roleAllows(DeviceToken token, Permission permission) =>
      token.role?.isAtLeast(permission.minimumRole) ?? false;
}
