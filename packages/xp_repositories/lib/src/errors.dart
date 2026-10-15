import 'package:xp_client/xp_client.dart';

/// What to tell the user about [error], thrown by a repository: the engine's
/// own words for an error it answered, the network's for one it did not.
String errorMessage(Object error) =>
    error is XpClientException ? error.message : '$error';
