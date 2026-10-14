import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/notify/notice.dart';
import 'package:xp_engine/src/notify/notice_factory.dart';
import 'package:xp_engine/src/notify/slack_webhook.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';

/// Tells the owner what matters (D-22).
///
/// It listens to the event log. For each event the [NoticeFactory] says is
/// worth telling, it appends a `notification.raised` event, which the app
/// shows as a macOS notification, and posts the same text to the Slack
/// webhook of the project, when the project has a `slack` credential.
///
/// The same notice (same key) within [dedupeWindow] is told once, so a state
/// that flaps does not repeat itself, and at most [slackPerMinute] messages go
/// to Slack in a minute, whatever the project. A Slack message is tried again
/// with growing waits; if it still fails the engine goes on and only
/// [onError] hears of it. Messages of one project go out in the order of the
/// events.
///
/// Secrets that are locked are told to the app only: the webhook is one of
/// the secrets that cannot be read then.
class Notifier {
  /// Creates the notifier.
  new({
    required this._events,
    required this._factory,
    required this._credentials,
    required this._secrets,
    required this._slack,
    required this._clock,
    this.dedupeWindow = const Duration(minutes: 15),
    this.slackPerMinute = 20,
    this.onError,
  });

  /// How long the same notice is not told again.
  final Duration dedupeWindow;

  /// The most messages sent to Slack in a minute.
  final int slackPerMinute;

  /// Hears about a failure that did not stop the engine.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final EventLog _events;
  final NoticeFactory _factory;
  final CredentialRepository _credentials;
  final SecretStore _secrets;
  final SlackSender _slack;
  final Clock _clock;

  StreamSubscription<SequencedEvent>? _eventSubscription;
  StreamSubscription<SecretsStatus>? _secretsSubscription;
  Future<void> _tail = Future.value();
  final _slackTails = <String, Future<void>>{};
  final _told = <String, DateTime>{};
  final _slackSent = <DateTime>[];
  var _stopped = false;

  /// Whether it listens.
  bool get isRunning => _eventSubscription != null;

  /// Starts listening. Does nothing if it does already.
  void start() {
    if (isRunning) return;
    _stopped = false;
    _eventSubscription = _events.subscribe().listen(
      (logged) => _enqueue(() async {
        final notice = await _factory.describe(logged.event);
        if (notice != null) await _tell(notice);
      }),
    );
    _secretsSubscription = _secrets.statusChanges.listen((status) {
      if (status == SecretsStatus.locked) {
        _enqueue(() => _tell(_factory.secretsLocked(), slack: false));
      }
    });
  }

  /// Stops listening and waits for what is under way. A Slack message that is
  /// waiting to be tried again is dropped.
  Future<void> stop() async {
    _stopped = true;
    await _eventSubscription?.cancel();
    await _secretsSubscription?.cancel();
    _eventSubscription = null;
    _secretsSubscription = null;
    await _tail;
    await Future.wait(_slackTails.values);
  }

  /// One at a time, in the order the events came.
  void _enqueue(Future<void> Function() work) {
    _tail = _tail.then((_) async {
      try {
        await work();
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }

  Future<void> _tell(Notice notice, {bool slack = true}) async {
    final now = _clock.now();
    _told.removeWhere((_, at) => now.difference(at) >= dedupeWindow);
    if (_told.containsKey(notice.key)) return;
    _told[notice.key] = now;
    _events.append(notice.toEvent());
    final projectId = notice.projectId;
    if (slack && projectId != null) {
      final previous = _slackTails[projectId] ?? Future<void>.value();
      late final Future<void> next;
      next = previous.then((_) => _post(projectId, notice)).whenComplete(() {
        _slackTails.removeWhere((_, tail) => identical(tail, next));
      });
      _slackTails[projectId] = next;
    }
  }

  bool _mayPostToSlack(DateTime now) {
    _slackSent.removeWhere((at) => now.difference(at) >= _minute);
    if (_slackSent.length >= slackPerMinute) return false;
    _slackSent.add(now);
    return true;
  }

  static const _minute = Duration(minutes: 1);

  Future<void> _post(String projectId, Notice notice) async {
    try {
      final url = await _webhookOf(projectId);
      if (url == null || !_mayPostToSlack(_clock.now())) return;
      await _slack.send(url, notice.slackText, cancelled: () => _stopped);
    } on SecretsLockedException {
      // The webhook cannot be read now; the app was told.
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  /// The webhook of a `slack` credential of [projectId] that no check
  /// rejected, or `null` if there is none.
  Future<Uri?> _webhookOf(String projectId) async {
    final usable = [
      for (final record in await _credentials.list(projectId: projectId))
        if (record.kind == CredentialKind.slack &&
            record.status != CredentialStatus.rejected)
          record,
    ];
    final record = usable.firstOrNull;
    if (record == null) return null;
    final material = await CredentialMaterial.load(
      record.kind,
      record.secretKey,
      record.account,
      _secrets,
    );
    return material is SlackMaterial ? Uri.tryParse(material.webhookUrl) : null;
  }
}
