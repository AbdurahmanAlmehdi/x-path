import 'package:xp_api/xp_api.dart';

/// A move between release states that D-17 does not allow.
class ReleaseTransitionException implements Exception {
  /// Creates the exception for the move [from] to [to].
  const new(this.from, this.to);

  /// The state the release was in.
  final ReleaseState from;

  /// The state it was asked to move to.
  final ReleaseState to;

  /// What is wrong, for the owner.
  String get message =>
      'A release cannot move from ${from.wire} to ${to.wire}.';

  @override
  String toString() => 'ReleaseTransitionException: $message';
}

/// The states of a release and the moves between them (D-17):
///
/// ```text
/// draft -> building -> uploaded -> in_review -> approved -> live -> merged
///                                      |
///                                      +-> rejected -> building (a new build)
/// ```
///
/// A store can also say `approved` or `live` before it said `in_review` (a
/// review that was quick, an internal Play track), so `uploaded` and
/// `in_review` may skip ahead. Any release that is not over can be
/// `abandoned`; `merged` and `abandoned` end it.
abstract final class ReleaseStateMachine {
  /// The moves a release in each state may make.
  static const transitions = <ReleaseState, Set<ReleaseState>>{
    ReleaseState.draft: {ReleaseState.building, ReleaseState.abandoned},
    ReleaseState.building: {ReleaseState.uploaded, ReleaseState.abandoned},
    ReleaseState.uploaded: {
      ReleaseState.inReview,
      ReleaseState.rejected,
      ReleaseState.approved,
      ReleaseState.live,
      ReleaseState.abandoned,
    },
    ReleaseState.inReview: {
      ReleaseState.rejected,
      ReleaseState.approved,
      ReleaseState.live,
      ReleaseState.abandoned,
    },
    ReleaseState.rejected: {ReleaseState.building, ReleaseState.abandoned},
    ReleaseState.approved: {ReleaseState.live, ReleaseState.abandoned},
    ReleaseState.live: {ReleaseState.merged, ReleaseState.abandoned},
    ReleaseState.merged: {},
    ReleaseState.abandoned: {},
  };

  /// Whether a release in [from] may move to [to].
  static bool canMove(ReleaseState from, ReleaseState to) =>
      transitions[from]!.contains(to);

  /// [to], if a release in [from] may move there.
  ///
  /// Throws a [ReleaseTransitionException] otherwise.
  static ReleaseState move(ReleaseState from, ReleaseState to) =>
      canMove(from, to) ? to : throw ReleaseTransitionException(from, to);
}
