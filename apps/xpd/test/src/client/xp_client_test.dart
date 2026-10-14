import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/test_engine.dart';

/// The shipped client against the shipped engine: what `xp`, `xp mcp` and the
/// desktop app will talk to it with.
void main() {
  late TestEngine engine;
  late XpClient client;

  setUp(() async {
    engine = await TestEngine.start();
    engine.folders['/work/app'] = projectFiles;
    client = XpClient(
      baseUrl: engine.uri,
      token: engine.secret,
      delay: (_) async {},
    );
  });
  tearDown(() async {
    client.close();
    await engine.close();
  });

  test('asks the engine whether it serves and which version it is', () async {
    expect(await client.health(), const HealthResponse());
    expect((await client.version()).apiVersion, apiVersion);
  });

  test('adds a project, lists it and reads it back', () async {
    final added = await client.addProject(
      const AddProjectRequest(path: '/work/app'),
    );

    expect(await client.listProjects(), [added]);
    expect(await client.getProject(added.id), added);
    expect(await client.scanProject(added.id), isA<Project>());
    await client.removeProject(added.id);
    expect(await client.listProjects(), isEmpty);
  });

  test('turns the error envelope of the engine into an ApiException', () async {
    await expectLater(
      client.getProject('prj_missing'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.code, 'code', ApiErrorCode.notFound),
      ),
    );
    await expectLater(
      XpClient(baseUrl: engine.uri, token: 'wrong').listProjects(),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', isTrue)),
    );
  });

  test('reads the log of a job with the real WebSocket', () async {
    engine.supervisor.handler = (process) async {
      await process.emit('one');
      await process.emit('two');
      return 0;
    };
    final job = await engine.startJob(['first']);
    await engine.jobs.whenFinished(job.id);

    final frames = await client.followJobLogs(job.id).toList();

    expect(frames.whereType<LogLineFrame>().map((line) => line.text), [
      'one',
      'two',
    ]);
    expect(frames.last, const LogEndFrame(state: JobState.succeeded));
    final resumed = await client.followJobLogs(job.id, after: 1).toList();
    expect(resumed.whereType<LogLineFrame>().map((line) => line.text), ['two']);
  });

  test('follows the events of the engine', () async {
    final events = StreamQueue(client.watchEvents());
    addTearDown(events.cancel);

    final opened = await events.next as EventReceived;
    expect(opened.event.event, isA<StreamOpened>());
    final added = await client.addProject(
      const AddProjectRequest(path: '/work/app'),
    );

    final seen = <EngineEvent>[];
    while (seen.whereType<ProjectScanned>().isEmpty) {
      seen.add(((await events.next) as EventReceived).event.event);
    }
    expect(seen.whereType<ProjectAdded>().single.projectId, added.id);
  });

  test('says when the engine cannot resume from a cursor', () async {
    final events = StreamQueue(client.watchEvents(after: 99999));
    addTearDown(events.cancel);

    expect(await events.next, const EventsResyncRequired());
    final opened = await events.next as EventReceived;
    expect(opened.event.event, isA<StreamOpened>());
  });

  test('resumes the events after the last one it handled', () async {
    final first = StreamQueue(client.watchEvents());
    final opened = await first.next as EventReceived;
    await client.addProject(const AddProjectRequest(path: '/work/app'));
    final added = await first.next as EventReceived;
    await first.cancel();
    await client.scanProject((await client.listProjects()).single.id);

    final resumed = StreamQueue(client.watchEvents(after: added.event.seq));
    addTearDown(resumed.cancel);
    await resumed.next; // the opening
    final replayed = await resumed.next as EventReceived;

    expect(opened.event.event, isA<StreamOpened>());
    expect(replayed.event.seq, added.event.seq + 1);
  });
}
