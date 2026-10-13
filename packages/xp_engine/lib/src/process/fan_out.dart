import 'dart:async';
import 'dart:collection';

/// What a [FanOut.watch] subscriber receives.
sealed class FanOutEvent<T> {
  const new();
}

/// A value that was added to the [FanOut].
final class FanOutItem<T> extends FanOutEvent<T> {
  /// Wraps [value].
  const new(this.value);

  /// The value.
  final T value;
}

/// Values the subscriber missed because it read too slowly.
final class FanOutGap<T> extends FanOutEvent<T> {
  /// Creates a gap.
  const new({required this.fromSeq, required this.toSeq, required this.count});

  /// The sequence number of the first dropped value.
  final int fromSeq;

  /// The sequence number of the last dropped value.
  final int toSeq;

  /// How many values were dropped.
  final int count;
}

/// Hands every added value to several subscribers without letting a slow one
/// grow memory without limit.
///
/// Every subscriber has a queue of at most `capacity` values. What happens when
/// it is full depends on the kind of subscriber:
///
/// - [subscribe] is for readers that must see everything, such as the log file
///   writer. [add] then waits until that reader has taken enough values, so
///   that the producer slows down: a process whose output nobody reads blocks
///   on its pipe instead of filling the engine's memory.
/// - [watch] is for live views, such as a WebSocket. When a watcher falls
///   behind its oldest queued values are dropped, and it receives one
///   [FanOutGap] in their place so that it knows to read them from the log.
///   It never slows the producer.
///
/// A subscriber starts receiving at the next value after it was created, and
/// from then on it queues values whether it listens yet or not; a lossless
/// subscriber that is never listened to blocks [add] once its queue is full.
/// Values must have increasing sequence numbers (`seqOf`).
class FanOut<T> {
  /// Creates a fan-out whose values are numbered by `seqOf`.
  new({required this._seqOf});

  final int Function(T value) _seqOf;
  final _subscribers = <_Subscriber<T, Object?>>[];
  var _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// A stream of every value added from now on, in order.
  ///
  /// [add] waits while the queue holds [capacity] values.
  Stream<T> subscribe({int capacity = 256}) {
    final subscriber = _Subscriber<T, T>(
      capacity: capacity,
      lossless: true,
      seqOf: _seqOf,
      wrap: (value) => value,
      makeGap: null,
      onRemove: _subscribers.remove,
    );
    _subscribers.add(subscriber);
    return subscriber.stream;
  }

  /// A stream of the values added from now on that keeps the newest
  /// [capacity] values and reports what it dropped as a [FanOutGap].
  Stream<FanOutEvent<T>> watch({int capacity = 256}) {
    final subscriber = _Subscriber<T, FanOutEvent<T>>(
      capacity: capacity,
      lossless: false,
      seqOf: _seqOf,
      wrap: FanOutItem.new,
      makeGap: (from, to, count) =>
          FanOutGap<T>(fromSeq: from, toSeq: to, count: count),
      onRemove: _subscribers.remove,
    );
    _subscribers.add(subscriber);
    return subscriber.stream;
  }

  /// Hands [value] to every subscriber and completes once every lossless
  /// subscriber has room for another one.
  ///
  /// Does nothing after [close].
  Future<void> add(T value) async {
    if (_closed) return;
    final subscribers = _subscribers.toList();
    for (final subscriber in subscribers) {
      subscriber.add(value);
    }
    await Future.wait<void>(subscribers.map((s) => s.hasRoom));
  }

  /// Ends the fan-out: subscribers receive what they have queued, then their
  /// streams end. Completes once the lossless subscribers have taken it all;
  /// it never waits for a [watch]er, which may be arbitrarily slow.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final subscribers = _subscribers.toList();
    for (final subscriber in subscribers) {
      subscriber.finish();
    }
    await Future.wait<void>([
      for (final subscriber in subscribers)
        if (subscriber.lossless) subscriber.done,
    ]);
  }
}

/// One subscriber's queue, delivered into a stream whenever its listener is
/// not paused.
class _Subscriber<T, E> {
  new({
    required this.capacity,
    required this.lossless,
    required this.seqOf,
    required this.wrap,
    required this.makeGap,
    required this.onRemove,
  }) {
    _controller = StreamController<E>(
      sync: true,
      onListen: _drain,
      onResume: _drain,
      onCancel: _cancel,
    );
  }

  final int capacity;
  final bool lossless;
  final int Function(T value) seqOf;
  final E Function(T value) wrap;
  final E Function(int fromSeq, int toSeq, int count)? makeGap;
  final void Function(_Subscriber<T, Object?> subscriber) onRemove;

  final _queue = Queue<T>();
  late final StreamController<E> _controller;
  final _done = Completer<void>();
  var _room = Completer<void>()..complete();
  var _gapFrom = 0;
  var _gapTo = 0;
  var _gapCount = 0;
  var _finished = false;
  var _ended = false;
  var _draining = false;

  Stream<E> get stream => _controller.stream;

  /// Completes when [FanOut.add] may go on.
  Future<void> get hasRoom => _room.future;

  /// Completes when the stream has ended or was cancelled.
  Future<void> get done => _done.future;

  void add(T value) {
    if (_ended) return;
    if (!lossless && _queue.length >= capacity) {
      final dropped = seqOf(_queue.removeFirst());
      if (_gapCount == 0) _gapFrom = dropped;
      _gapTo = dropped;
      _gapCount++;
    }
    _queue.add(value);
    if (lossless && _queue.length >= capacity && _room.isCompleted) {
      _room = Completer<void>();
    }
    _drain();
  }

  void finish() {
    _finished = true;
    _drain();
  }

  void _drain() {
    if (_draining) return;
    _draining = true;
    try {
      while (!_ended && !_controller.isPaused) {
        if (_gapCount > 0) {
          final count = _gapCount;
          _gapCount = 0;
          _controller.add(makeGap!(_gapFrom, _gapTo, count));
        } else if (_queue.isNotEmpty) {
          _controller.add(wrap(_queue.removeFirst()));
        } else {
          break;
        }
      }
    } finally {
      _draining = false;
    }
    if (_ended) return;
    if (_queue.length < capacity && !_room.isCompleted) _room.complete();
    if (_finished && _queue.isEmpty && _gapCount == 0) {
      _detach();
      unawaited(_controller.close().whenComplete(_complete));
    }
  }

  void _cancel() {
    _queue.clear();
    _gapCount = 0;
    _detach();
    _complete();
  }

  /// Takes the subscriber out of the fan-out: it receives nothing more.
  void _detach() {
    if (_ended) return;
    _ended = true;
    onRemove(this);
    if (!_room.isCompleted) _room.complete();
  }

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }
}
