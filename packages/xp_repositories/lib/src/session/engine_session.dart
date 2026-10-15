import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/cache/snapshot_cache.dart';
import 'package:xp_repositories/src/engines/engine_profile.dart';
import 'package:xp_repositories/src/session/engine_status.dart';
import 'package:xp_repositories/src/snapshot.dart';

Stream<void> _defaultHeartbeat() =>
    Stream<void>.periodic(const Duration(seconds: 10));

/// The app's connection to one engine: the client, the one event stream the
/// repositories share, the [status] the connection banner shows, and the
/// offline cache.
///
/// Switching engines closes the session and opens another one: [close] ends
/// every stream it gave out, so nothing of the old engine reaches the new
/// screens.
class EngineSession {
  /// Creates a session with [profile] over [client], caching in [cache].
  ///
  /// `heartbeat` ticks when the session checks `GET /health` (every 10 s by
  /// default); the engine counts as unreachable after [unreachableAfter]
  /// failed checks in a row.
  new({
    required this.profile,
    required this.client,
    required this.cache,
    this._heartbeat = _defaultHeartbeat,
    this.unreachableAfter = 2,
  });

  /// A session with the real client of [profile] for [token], caching in a
  /// folder of its own under [cacheDirectory].
  factory connect({
    required EngineProfile profile,
    required String token,
    required String cacheDirectory,
  }) => EngineSession(
    profile: profile,
    client: XpClient(baseUrl: profile.url, token: token),
    cache: FileSnapshotCache(
      p.join(
        cacheDirectory,
        profile.id.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_'),
      ),
    ),
  );

  /// The engine.
  final EngineProfile profile;

  /// The client of the engine. The repositories use it through [call] and
  /// [watch], which keep [status] up to date.
  final XpClient client;

  /// The offline cache of this engine.
  final SnapshotCache cache;

  /// How many failed checks in a row make the engine unreachable.
  final int unreachableAfter;

  final Stream<void> Function() _heartbeat;
  final _statusController = StreamController<EngineStatus>.broadcast();
  final _eventController = StreamController<EngineEvent>.broadcast();
  final _refreshController = StreamController<void>.broadcast();
  final _watchers = <StreamController<Object?>>{};
  StreamSubscription<EventStreamItem>? _eventSubscription;
  StreamSubscription<void>? _heartbeatSubscription;
  EngineStatus _status = EngineStatus.connecting;
  var _failures = 0;
  var _closed = false;

  /// How the connection stands now.
  EngineStatus get status => _status;

  /// Every change of [status].
  Stream<EngineStatus> get statusChanges => _statusController.stream;

  /// What happens on the engine (`GET /events`), without the frame that
  /// opens each connection.
  Stream<EngineEvent> get events => _eventController.stream;

  /// Fires when what the app holds may be out of date: the engine could not
  /// resume the event stream, or it answers again after an outage.
  Stream<void> get refreshes => _refreshController.stream;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Checks the engine and starts following its events and its health. A
  /// closed session stays closed.
  Future<void> start() async {
    if (_closed) return;
    _eventSubscription = client.watchEvents().listen(
      _onEventItem,
      onError: reportFailure,
    );
    _heartbeatSubscription = _heartbeat().listen((_) => unawaited(check()));
    await check();
  }

  /// Asks `GET /health` now and updates [status].
  Future<void> check() async {
    try {
      await client.health();
      _reachable();
    } on XpClientException catch (error) {
      reportFailure(error);
    }
  }

  /// Ends every stream of the session and closes the client.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventSubscription?.cancel();
    await _heartbeatSubscription?.cancel();
    // Not awaited: a controller finishes closing only once its listener
    // has taken the done event, and a listener may be paused.
    for (final watcher in [..._watchers]) {
      unawaited(watcher.close());
    }
    await _statusController.close();
    await _eventController.close();
    await _refreshController.close();
    client.close();
  }

  /// Records that a request to the engine succeeded.
  void reportSuccess() {
    _failures = 0;
    final offline = _isOffline;
    _setStatus(EngineStatus.connected);
    if (offline && !_closed) _refreshController.add(null);
  }

  bool get _isOffline =>
      _status == EngineStatus.reconnecting ||
      _status == EngineStatus.unreachable ||
      _status == EngineStatus.rejected;

  /// Records that a request to the engine failed with [error].
  void reportFailure(Object error) {
    switch (error) {
      case ConnectionException():
        _failures++;
        _setStatus(
          _status == EngineStatus.connecting || _failures >= unreachableAfter
              ? EngineStatus.unreachable
              : EngineStatus.reconnecting,
        );
      case ApiException(code: ApiErrorCode.secretsLocked):
        _setStatus(EngineStatus.secretsLocked);
      case ApiException(code: ApiErrorCode.unauthorized):
        _setStatus(EngineStatus.rejected);
      default:
        break;
    }
  }

  /// Runs [request] against the engine, keeping [status] up to date.
  /// Errors reach the caller.
  Future<T> call<T>(Future<T> Function(XpClient client) request) async {
    try {
      final result = await request(client);
      reportSuccess();
      return result;
    } on Object catch (error) {
      reportFailure(error);
      rethrow;
    }
  }

  /// A stream of what [fetch] answers: first the value cached under [key],
  /// if any, then the engine's, and again whenever an event for which
  /// [refreshOn] is true happens or the session [refreshes].
  ///
  /// [encode] and [decode] convert the value to and from its cached JSON
  /// form. While the engine cannot be reached nothing is emitted, so the last
  /// value stays; an error the engine answered (a missing job) is emitted as
  /// an error. The stream ends when the session closes.
  Stream<Snapshot<T>> watch<T>({
    required String key,
    required Future<T> Function(XpClient client) fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
    required bool Function(EngineEvent event) refreshOn,
  }) {
    late final StreamController<Snapshot<T>> controller;
    final subscriptions = <StreamSubscription<void>>[];
    var loading = false;
    var again = false;

    Future<void> loadOnce() async {
      try {
        final value = await call(fetch);
        if (controller.isClosed) return;
        controller.add(Snapshot(value));
        await cache.write(key, encode(value));
      } on ConnectionException {
        // The status says so; the last value stays.
      } on ApiException catch (error) {
        if (error.code != ApiErrorCode.secretsLocked &&
            error.code != ApiErrorCode.unauthorized &&
            !controller.isClosed) {
          controller.addError(error);
        }
      } on Object catch (error, stackTrace) {
        // A bug (an answer that does not parse): the listener hears of it.
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    Future<void> load() async {
      if (loading) {
        again = true;
        return;
      }
      loading = true;
      do {
        again = false;
        await loadOnce();
      } while (again && !controller.isClosed);
      loading = false;
    }

    Future<void> begin() async {
      final cached = await cache.read(key);
      if (cached != null && !controller.isClosed) {
        controller.add(Snapshot(decode(cached), cached: true));
      }
      if (controller.isClosed) return;
      subscriptions
        ..add(events.where(refreshOn).listen((_) => unawaited(load())))
        ..add(refreshes.listen((_) => unawaited(load())));
      await load();
    }

    controller = StreamController<Snapshot<T>>(
      onListen: () {
        if (_closed) {
          unawaited(controller.close());
          return;
        }
        _watchers.add(controller);
        unawaited(begin());
      },
      onCancel: () {
        _watchers.remove(controller);
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
      },
    );
    return controller.stream;
  }

  void _onEventItem(EventStreamItem item) {
    switch (item) {
      case EventReceived(event: SequencedEvent(event: StreamOpened())):
        _reachable();
      case EventReceived(:final event):
        _eventController.add(event.event);
      case EventsResyncRequired():
        _refreshController.add(null);
    }
  }

  void _reachable() {
    _failures = 0;
    if (_status == EngineStatus.connecting ||
        _status == EngineStatus.reconnecting ||
        _status == EngineStatus.unreachable) {
      final offline = _isOffline;
      _setStatus(EngineStatus.connected);
      if (offline) _refreshController.add(null);
    }
  }

  void _setStatus(EngineStatus status) {
    if (_closed || status == _status) return;
    _status = status;
    _statusController.add(status);
  }
}
