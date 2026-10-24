import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/approvals_repository.dart';
import 'package:xp_repositories/src/credentials_repository.dart';

/// What to tell the user about an error nobody expected: its own text is
/// for the log, not for a person.
const unexpectedErrorMessage =
    'Something went wrong that XPath did not expect. Try again; if it keeps '
    'happening, restart XPath.';

/// What to tell the user about [error], thrown by a repository: the engine's
/// own words for an error it answered, with what it says to do (UX-05), the
/// network's for one it did not, and [unexpectedErrorMessage] for anything
/// else.
String errorMessage(Object error) => switch (error) {
  ApiException(:final message, :final hint?) => '$message $hint',
  XpClientException(:final message) => message,
  ApprovalAlreadyDecided(:final message) => message,
  CredentialInUse(:final message) => message,
  _ => unexpectedErrorMessage,
};
