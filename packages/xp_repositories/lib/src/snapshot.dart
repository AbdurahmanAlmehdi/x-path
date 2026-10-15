import 'package:equatable/equatable.dart';

/// One value a repository stream emits, and where it came from.
///
/// A stream starts with the value cached from the last time the engine
/// answered, if there is one ([cached] is `true`), then follows the engine
/// ([cached] is `false`). While the engine cannot be reached the stream
/// emits nothing new, so the last value stays on screen, read-only.
class Snapshot<T> extends Equatable {
  /// Creates a snapshot of [value].
  const new(this.value, {this.cached = false});

  /// The data.
  final T value;

  /// Whether [value] was read from the offline cache rather than from the
  /// engine.
  final bool cached;

  @override
  List<Object?> get props => [value, cached];
}
