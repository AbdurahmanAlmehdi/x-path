import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/xp_repositories.dart';

class MockXpClient extends Mock implements XpClient;

final at = DateTime.utc(2026, 10, 13, 14, 2);

final remote = EngineProfile(
  id: 'mac-mini:7480',
  name: 'mac-mini',
  url: Uri.parse('http://mac-mini:7480'),
);

const project = Project(
  id: 'prj_1',
  githubRepoId: 1,
  fullName: 'acme/app',
  remote: 'git@github.com:acme/app.git',
  defaultBaseBranch: 'main',
);

const offline = ConnectionException('Connection refused.');

const locked = ApiException(
  'Secrets are locked.',
  statusCode: 503,
  code: ApiErrorCode.secretsLocked,
);

const unauthorized = ApiException(
  'Unknown token.',
  statusCode: 401,
  code: ApiErrorCode.unauthorized,
);

const notFound = ApiException(
  'No such thing.',
  statusCode: 404,
  code: ApiErrorCode.notFound,
);

/// A session over a [MockXpClient] whose events and heartbeat the test
/// drives.
class Harness {
  new() {
    when(client.watchEvents).thenAnswer((_) => events.stream);
    when(client.health).thenAnswer((_) async => const HealthResponse());
    session = EngineSession(
      profile: remote,
      client: client,
      cache: cache,
      heartbeat: () => heartbeat.stream,
    );
  }

  final client = MockXpClient();
  final events = StreamController<EventStreamItem>();
  final heartbeat = StreamController<void>();
  final cache = MemorySnapshotCache();
  late final EngineSession session;

  /// Sends [event] as the engine would.
  void send(EngineEvent event, {int seq = 1}) =>
      events.add(EventReceived(SequencedEvent(seq: seq, at: at, event: event)));

  Future<void> dispose() async {
    await session.close();
    // Never awaited: a controller nobody listened to never finishes closing.
    unawaited(events.close());
    unawaited(heartbeat.close());
  }
}

/// Lets pending microtasks and zero-length timers run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
