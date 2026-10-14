import 'package:xp_api/xp_api.dart';

/// The engine's end of a runner's connection: where it sends frames and how
/// it closes the socket. `apps/xpd` has the WebSocket implementation.
abstract interface class RunnerLink {
  /// Sends [frame] to the runner.
  ///
  /// Throws if the connection is closed.
  void send(EngineFrame frame);

  /// Closes the connection with a WebSocket close [code] and [reason].
  Future<void> close(int code, String reason);
}

/// A [RunnerLink] that keeps what it was told, for tests.
class FakeRunnerLink implements RunnerLink {
  /// The frames sent, in order.
  final sent = <EngineFrame>[];

  /// The close code, or `null` while open.
  int? closeCode;

  /// The close reason, or `null` while open.
  String? closeReason;

  /// Whether sending fails, as it does on a connection that broke.
  bool failToSend = false;

  /// Whether the link was closed.
  bool get isClosed => closeCode != null;

  /// The sent frames of type [T].
  List<T> sentOf<T extends EngineFrame>() => sent.whereType<T>().toList();

  @override
  void send(EngineFrame frame) {
    if (failToSend || isClosed) throw StateError('The connection is closed.');
    sent.add(frame);
  }

  @override
  Future<void> close(int code, String reason) async {
    closeCode ??= code;
    closeReason ??= reason;
  }
}
