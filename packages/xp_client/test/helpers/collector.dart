import 'dart:async';

/// Listens to `stream` at once and keeps what it emits.
class Collector<T> {
  new(Stream<T> stream) {
    _subscription = stream.listen(
      items.add,
      onError: errors.add,
      onDone: () => isDone = true,
    );
  }

  late final StreamSubscription<T> _subscription;

  /// What the stream emitted.
  final items = <T>[];

  /// The errors it emitted.
  final errors = <Object>[];

  /// Whether the stream ended.
  bool isDone = false;

  Future<void> cancel() => _subscription.cancel();
}
