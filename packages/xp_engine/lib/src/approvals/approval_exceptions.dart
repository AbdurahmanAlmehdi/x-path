import 'package:xp_api/xp_api.dart';

/// An approval operation failed. The message is for the owner.
class ApprovalException implements Exception {
  /// Creates the exception with a [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ApprovalException: $message';
}

/// There is no such approval.
class ApprovalNotFoundException extends ApprovalException {
  /// Creates the exception for [id].
  const new(this.id) : super('There is no approval $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'ApprovalNotFoundException: $message';
}

/// The token's kind may not do this (D-13): an `mcp` or `runner` token never
/// approves, denies or changes gates, and a `cli` token never loosens them.
class ApprovalForbiddenException extends ApprovalException {
  /// Creates the exception with a [message] that says what the kind may do.
  const new(super.message);

  @override
  String toString() => 'ApprovalForbiddenException: $message';
}

/// The approval was decided already, or it expired: the first decision wins
/// (D-13).
class ApprovalAlreadyDecidedException extends ApprovalException {
  /// Creates the exception for [approval], which is as it stands.
  new(this.approval) : super(_describe(approval));

  /// The approval as it stands: the decision that won.
  final Approval approval;

  static String _describe(Approval approval) {
    final by = approval.decidedBy;
    return switch (approval.state) {
      ApprovalState.expired =>
        'Approval ${approval.id} expired: nobody decided within 24 hours, '
            'which counts as denied.',
      _ =>
        'Approval ${approval.id} was ${approval.state.wire}'
            '${by == null ? '' : ' by ${by.name} (${by.kind.name})'} '
            'already: the first decision wins.',
    };
  }

  @override
  String toString() => 'ApprovalAlreadyDecidedException: $message';
}

/// The request is malformed: it names an action that is not a gate.
class ApprovalRequestException extends ApprovalException {
  /// Creates the exception with a [message].
  const new(super.message);

  @override
  String toString() => 'ApprovalRequestException: $message';
}
