import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/approvals_repository.dart';
import 'package:xp_repositories/src/credentials_repository.dart';
import 'package:xp_repositories/src/projects_repository.dart';

/// What to tell the user about [error], thrown by a repository: the engine's
/// own words for an error it answered, the network's for one it did not.
String errorMessage(Object error) => switch (error) {
  XpClientException(:final message) => message,
  ApprovalAlreadyDecided(:final message) => message,
  CredentialInUse(:final message) => message,
  SshUrlRequired(:final message) => message,
  _ => '$error',
};
