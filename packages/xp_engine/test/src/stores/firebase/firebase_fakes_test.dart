import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late FakeFirebaseAppDistribution firebase;

  setUp(() => firebase = FakeFirebaseAppDistribution());

  Stream<List<int>> content() => Stream.fromIterable([
    [1, 2],
    [3],
  ]);

  test('uploads numbered releases and records the bytes', () async {
    final first = await firebase.uploadRelease(
      'projects/1/apps/a',
      content: content,
      length: 3,
      fileName: 'dev.apk',
    );

    expect(first.done, isTrue);
    expect(first.release?.name, 'projects/1/apps/a/releases/rel-1');
    expect(first.result, FirebaseUploadResult.created);
    expect(firebase.uploads, [
      [1, 2, 3],
    ]);
    expect(firebase.uploadLengths, [3]);
    expect(firebase.uploadNames, ['dev.apk']);
    expect(firebase.calls, ['uploadRelease projects/1/apps/a 3 dev.apk']);
  });

  test('answers the queued upload operations first', () async {
    firebase.uploadOperations.add(const FirebaseOperation(name: 'op'));

    final operation = await firebase.uploadRelease(
      'projects/1/apps/a',
      content: content,
      length: 3,
      fileName: 'dev.apk',
    );

    expect(operation, const FirebaseOperation(name: 'op'));
  });

  test('polls: the queued answers in order, the last one repeats', () async {
    expect(await firebase.operation('op'), const FirebaseOperation(name: 'op'));

    firebase.operationsOf['op'] = [
      const FirebaseOperation(name: 'op'),
      const FirebaseOperation(name: 'op', done: true),
    ];

    expect((await firebase.operation('op')).done, isFalse);
    expect((await firebase.operation('op')).done, isTrue);
    expect((await firebase.operation('op')).done, isTrue);
  });

  test('lists, sets notes, distributes and verifies', () async {
    firebase.releasesOf['projects/1/apps/a'] = const [
      FirebaseRelease(name: 'r'),
    ];

    expect(
      await firebase.releases('projects/1/apps/a', pages: 2),
      hasLength(1),
    );
    expect(await firebase.releases('projects/1/apps/b'), isEmpty);
    expect(
      (await firebase.updateReleaseNotes('r', 'Fixes')).releaseNotes,
      'Fixes',
    );
    await firebase.distribute(
      'r',
      testerEmails: ['a@b.co'],
      groupAliases: ['qa'],
    );
    await firebase.distribute('r');
    await firebase.verifyAccess();

    expect(firebase.notes, ['r Fixes']);
    expect(firebase.distributions, [
      'r testers=a@b.co groups=qa',
      'r testers= groups=',
    ]);
    expect(firebase.calls.last, 'verifyAccess');
  });

  test('throws a queued failure once', () async {
    firebase.failures['verifyAccess'] = const FirebaseAuthException('no');

    await expectLater(
      firebase.verifyAccess(),
      throwsA(isA<FirebaseAuthException>()),
    );
    await firebase.verifyAccess();
  });
}
