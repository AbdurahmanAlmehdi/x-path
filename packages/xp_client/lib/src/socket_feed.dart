import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_client/src/exceptions.dart';

/// What a feed does after it handled one frame.
enum FeedNext {
  /// Keep reading this connection.
  read,

  /// Drop this connection and open a new one at once.
  reconnect,

  /// The feed is complete: close the connection and end the stream.
  finish,
}

/// What a feed does when it could not open a connection.
enum OpenFailure {
  /// Open a new connection at once.
  retryNow,

  /// Open a new connection after the back-off delay.
  retryLater,

  /// End the stream with the error.
  fail,
}

/// A stream fed by a WebSocket that reconnects when it drops.
///
/// A subclass says how to open the connection (resuming from the cursor it
/// keeps), what a frame means and what to do about failures. The stream starts
/// when someone listens and ends when the subclass says the feed is complete,
/// when a failure cannot be retried or when the listener cancels.
abstract class SocketFeed<T> {
  /// Creates a feed. `delay` waits for the back-off: it doubles from
  /// `initialDelay` up to `maxDelay` while connections keep failing.
  new({
    required this._delay,
    required this._initialDelay,
    required this._maxDelay,
  }) {
    _controller = StreamController<T>(onListen: _run, onCancel: _stop);
  }

  final Future<void> Function(Duration) _delay;
  final Duration _initialDelay;
  final Duration _maxDelay;
  late final StreamController<T> _controller;
  WebSocketChannel? _channel;
  var _stopped = false;

  /// The items, once someone listens.
  Stream<T> get stream => _controller.stream;

  /// Opens a connection that resumes from the current cursor.
  Future<WebSocketChannel> open();

  /// Handles one frame: emit what it means with [emit].
  FeedNext handle(Map<String, dynamic> frame, void Function(T item) emit);

  /// Handles the failure to open a connection. The default retries what is
  /// the engine's or the network's fault (5xx) and fails the rest.
  OpenFailure onOpenFailure(ApiException error, void Function(T item) emit) =>
      error.statusCode >= 500 ? OpenFailure.retryLater : OpenFailure.fail;

  /// Handles the engine closing the connection with [code]. Returns whether to
  /// reconnect at once instead of after the back-off delay.
  bool onClosed(int? code, void Function(T item) emit) => false;

  void _emit(T item) {
    if (!_stopped) _controller.add(item);
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_stopped) {
      var immediately = false;
      try {
        final channel = await open();
        if (_stopped) {
          unawaited(channel.sink.close());
          break;
        }
        _channel = channel;
        final read = await _read(channel);
        _channel = null;
        if (read.finished) break;
        if (read.frames > 0) failures = 0;
        immediately = read.reconnect;
      } on ApiException catch (error) {
        switch (onOpenFailure(error, _emit)) {
          case OpenFailure.retryNow:
            immediately = true;
          case OpenFailure.retryLater:
            break;
          case OpenFailure.fail:
            _controller.addError(error);
            await _controller.close();
            return;
        }
      } on ConnectionException {
        // The network is down or the engine is restarting: try again.
      }
      if (immediately) continue;
      failures++;
      await _delay(_backoff(failures));
    }
    await _controller.close();
  }

  Duration _backoff(int failures) {
    var delay = _initialDelay;
    for (var i = 1; i < failures && delay < _maxDelay; i++) {
      delay *= 2;
    }
    return delay < _maxDelay ? delay : _maxDelay;
  }

  Future<_Read> _read(WebSocketChannel channel) {
    final done = Completer<_Read>();
    var frames = 0;
    late StreamSubscription<dynamic> subscription;

    void leave({bool reconnect = false, bool finished = false}) {
      if (done.isCompleted) return;
      unawaited(subscription.cancel());
      unawaited(channel.sink.close().catchError((Object _) {}));
      done.complete(
        _Read(frames: frames, reconnect: reconnect, finished: finished),
      );
    }

    subscription = channel.stream.listen(
      (message) {
        if (_stopped || done.isCompleted) return;
        final FeedNext next;
        try {
          final frame = jsonDecode('$message') as Map<String, dynamic>;
          next = handle(frame, _emit);
        } on Object {
          // A frame this client cannot read, for example one of a newer
          // engine: skip it. The cursor stays where it is.
          return;
        }
        frames++;
        switch (next) {
          case FeedNext.read:
            break;
          case FeedNext.reconnect:
            leave(reconnect: true);
          case FeedNext.finish:
            leave(finished: true);
        }
      },
      onError: (Object _) => leave(),
      onDone: () {
        if (done.isCompleted) return;
        final reconnect = onClosed(channel.closeCode, _emit);
        leave(reconnect: reconnect);
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Future<void> _stop() async {
    _stopped = true;
    final channel = _channel;
    if (channel != null) {
      await channel.sink.close().catchError((Object _) {});
    }
  }
}

final class _Read {
  const new({
    required this.frames,
    required this.reconnect,
    required this.finished,
  });

  final int frames;
  final bool reconnect;
  final bool finished;
}
