import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';

/// What the engine of an [EngineSession] says the owner should hear about,
/// for the app to show as macOS notifications (U6b): the notifications the
/// engine raises (D-22) and the runner events the app turns into notices.
class NoticesRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The [NotificationRaised], [RunnerLeaseLost] and
  /// [RunnerCapabilitiesChanged] events, as they arrive.
  Stream<EngineEvent> watchNotices() => _session.events.where(
    (event) =>
        event is NotificationRaised ||
        event is RunnerLeaseLost ||
        event is RunnerCapabilitiesChanged,
  );
}
