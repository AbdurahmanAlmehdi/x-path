import 'package:xp_api/xp_api.dart';

/// A credential operation failed. The message never contains a secret.
class CredentialException implements Exception {
  /// Creates an exception with [message] and, if there is one, what to do.
  const new(this.message, {this.fix});

  /// What went wrong.
  final String message;

  /// What the owner can do about it.
  final String? fix;

  /// The message with the fix, as one text for the owner.
  String get described => fix == null ? message : '$message $fix';

  @override
  String toString() => 'CredentialException: $message';
}

/// There is no such credential, app or flavor.
class CredentialNotFoundException extends CredentialException {
  /// Creates an exception with [message].
  const new(super.message);
}

/// The request is malformed: a field is missing or of the wrong type.
class CredentialRequestException extends CredentialException {
  /// Creates an exception with [message].
  const new(super.message);
}

/// The credential was not stored: the store or the tool it is for refused it,
/// or it is not usable (a key that is not a key, a token with the wrong
/// prefix).
class CredentialRejectedException extends CredentialException {
  /// Creates an exception with [message] and [fix].
  const new(super.message, {super.fix});
}

/// The credential could not be checked because the store or the tool could
/// not be reached, so nothing was stored.
class CredentialUnreachableException extends CredentialException {
  /// Creates an exception with [message] and [fix].
  const new(super.message, {super.fix});
}

/// Another credential has the name already (names are unique regardless of
/// case).
class CredentialConflictException extends CredentialException {
  /// Creates an exception with [message].
  const new(super.message);
}

/// The credential is used by flavors, so it was not deleted.
class CredentialInUseException extends CredentialException {
  /// Creates an exception for the flavors [usedBy].
  const new(super.message, this.usedBy);

  /// The flavors that use the credential.
  final List<CredentialUsage> usedBy;
}

/// The device token's kind may not change credentials: only the app and `xp`
/// do (an MCP client reads them; a runner does not reach them).
class CredentialForbiddenException extends CredentialException {
  /// Creates an exception with [message].
  const new(super.message);
}
