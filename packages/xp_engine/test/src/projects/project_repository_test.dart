import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  ProjectRecord record(String id, int repoId) => ProjectRecord(
    id: id,
    githubRepoId: repoId,
    fullName: 'octo/$id',
    remote: 'https://github.com/octo/$id.git',
    githubDefaultBranch: 'main',
    scan: const ProjectProfile(),
    findings: const [],
    scannedAt: DateTime.utc(2026),
  );

  late InMemoryProjectRepository repository;

  setUp(() => repository = InMemoryProjectRepository());

  test('lists projects in the order they were added', () async {
    await repository.add(record('b', 2));
    await repository.add(record('a', 1));

    expect((await repository.list()).map((r) => r.id), ['b', 'a']);
  });

  test('finds a project by id and by GitHub repository id', () async {
    await repository.add(record('a', 1));

    expect((await repository.get('a'))!.githubRepoId, 1);
    expect(await repository.get('nope'), isNull);
    expect((await repository.findByGithubRepoId(1))!.id, 'a');
    expect(await repository.findByGithubRepoId(2), isNull);
  });

  test('refuses a second project for a repository', () async {
    await repository.add(record('a', 1));

    expect(() => repository.add(record('b', 1)), throwsStateError);
  });

  test('updates a stored project and refuses an unknown one', () async {
    await repository.add(record('a', 1));

    await repository.update(record('a', 1).copyWith(fullName: 'octo/new'));

    expect((await repository.get('a'))!.fullName, 'octo/new');
    expect(() => repository.update(record('z', 9)), throwsStateError);
  });

  test('removes a project and says whether it was there', () async {
    await repository.add(record('a', 1));

    expect(await repository.remove('a'), isTrue);
    expect(await repository.remove('a'), isFalse);
    expect(await repository.list(), isEmpty);
  });
}
