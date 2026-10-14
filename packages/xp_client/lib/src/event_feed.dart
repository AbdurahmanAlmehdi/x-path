import 'package:equatable/equatable.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/src/exceptions.dart';
import 'package:xp_client/src/socket_feed.dart';

/// One thing `XpClient.watchEvents` tells its listener.
sealed class EventStreamItem extends Equatable {
  const new();
}

/// The engine sent `event`. The first one of every connection is a
/// `StreamOpened`.
final class EventReceived extends EventStreamItem {
  /// Creates the item.
  const new(this.event);

  /// The event with its place in the log.
  final SequencedEvent event;

  @override
  List<Object?> get props => [event];
}

/// The engine can no longer resume from where the stream was (it keeps a
/// window of events, or it restarted): everything the listener holds may be
/// out of date, so it must reload its state over HTTP. The stream has already
/// reconnected without a cursor and carries on with live events.
final class EventsResyncRequired extends EventStreamItem {
  /// Creates the item.
  const new();

  @override
  List<Object?> get props => const [];
}

/// The feed behind `XpClient.watchEvents`: `GET /events`, resumed with
/// `after=<seq of the last event handled>`.
class EventFeed extends SocketFeed<EventStreamItem> {
  /// Creates the feed. It opens connections with `connect` and resumes after
  /// the event `after`, if given.
  new({
    required this._connect,
    required int? after,
    required super.delay,
    required super.initialDelay,
    required super.maxDelay,
  }) : _cursor = after;

  final Future<WebSocketChannel> Function(int? after) _connect;
  int? _cursor;

  @override
  Future<WebSocketChannel> open() => _connect(_cursor);

  @override
  FeedNext handle(
    Map<String, dynamic> frame,
    void Function(EventStreamItem item) emit,
  ) {
    final sequenced = SequencedEvent.fromJson(frame);
    if (sequenced.event is StreamOpened) {
      // Its `seq` is the head of the log, not an event the listener handled:
      // only a stream without a cursor starts from there.
      _cursor ??= sequenced.seq;
    } else {
      final cursor = _cursor;
      if (cursor != null && sequenced.seq <= cursor) return FeedNext.read;
      _cursor = sequenced.seq;
    }
    emit(EventReceived(sequenced));
    return FeedNext.read;
  }

  @override
  OpenFailure onOpenFailure(
    ApiException error,
    void Function(EventStreamItem item) emit,
  ) {
    if (!error.isResyncRequired) return super.onOpenFailure(error, emit);
    _resync(emit);
    return OpenFailure.retryNow;
  }

  @override
  bool onClosed(int? code, void Function(EventStreamItem item) emit) {
    if (code != eventStreamResyncCloseCode) return false;
    _resync(emit);
    return true;
  }

  void _resync(void Function(EventStreamItem item) emit) {
    _cursor = null;
    emit(const EventsResyncRequired());
  }
}
