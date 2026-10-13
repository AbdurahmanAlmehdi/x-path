import 'package:equatable/equatable.dart';

/// WebSocket close code of an `/events` stream whose cursor can no longer be
/// resumed. The HTTP counterpart is `409 resync_required`.
const eventStreamResyncCloseCode = 4409;

/// Something that happened in the engine, as streamed over `/events`.
///
/// Concrete events are added phase by phase. A client that meets a type it
/// does not know gets an [UnknownEvent], so an older client keeps working
/// against a newer engine.
sealed class EngineEvent extends Equatable {
  const new();

  /// Reads the event of [type] from its [payload].
  factory fromJson(String type, Map<String, dynamic> payload) => switch (type) {
    EngineStarted.eventType => EngineStarted(
      version: payload['version'] as String,
      apiVersion: payload['apiVersion'] as String,
    ),
    StreamOpened.eventType => const StreamOpened(),
    _ => UnknownEvent(type: type, payload: payload),
  };

  /// The wire name, for example `engine.started`.
  String get type;

  /// The event-specific JSON object.
  Map<String, dynamic> get payload;
}

/// The engine finished starting.
final class EngineStarted extends EngineEvent {
  /// Creates the event.
  const new({required this.version, required this.apiVersion});

  /// The wire name of this event.
  static const eventType = 'engine.started';

  /// The engine's version.
  final String version;

  /// The major version of the API the engine serves.
  final String apiVersion;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'version': version,
    'apiVersion': apiVersion,
  };

  @override
  List<Object?> get props => [version, apiVersion];
}

/// The first frame of every `/events` stream.
///
/// It is not a log entry: its `seq` is the head of the log when the stream
/// opened. A client with no cursor yet stores it as its cursor.
final class StreamOpened extends EngineEvent {
  /// Creates the event.
  const new();

  /// The wire name of this event.
  static const eventType = 'stream.opened';

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => const {};

  @override
  List<Object?> get props => const [];
}

/// An event whose type this client does not know.
final class UnknownEvent extends EngineEvent {
  /// Creates the event.
  const new({required this.type, required this.payload});

  @override
  final String type;

  @override
  final Map<String, dynamic> payload;

  @override
  List<Object?> get props => [type, payload];
}

/// An [EngineEvent] with its place in the event log.
///
/// The wire form is `{"seq": 7, "at": "...", "type": "...", "payload": {}}`.
/// `seq` grows by one per logged event, so a client that saw `seq` 7 resumes
/// with `?after=7`.
class SequencedEvent extends Equatable {
  /// Creates a sequenced event.
  const new({required this.seq, required this.at, required this.event});

  /// Reads a sequenced event from its JSON form.
  factory fromJson(Map<String, dynamic> json) => SequencedEvent(
    seq: json['seq'] as int,
    at: DateTime.parse(json['at'] as String),
    event: EngineEvent.fromJson(
      json['type'] as String,
      json['payload'] as Map<String, dynamic>,
    ),
  );

  /// Position in the event log, starting at 1.
  final int seq;

  /// When the event happened, in UTC.
  final DateTime at;

  /// What happened.
  final EngineEvent event;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'seq': seq,
    'at': at.toUtc().toIso8601String(),
    'type': event.type,
    'payload': event.payload,
  };

  @override
  List<Object?> get props => [seq, at, event];
}
