import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryReleaseModelRepository repository;

  setUp(() => repository = InMemoryReleaseModelRepository(['prj_1']));

  test('gives the default model until one is saved', () async {
    expect(await repository.get('prj_1'), const ReleaseModel());

    const model = ReleaseModel(tagPattern: 'rel-{version}-{build}');
    await repository.save('prj_1', model);

    expect(await repository.get('prj_1'), model);
  });

  test('refuses an unknown project', () {
    expect(repository.get('nope'), throwsA(isA<ProjectNotFoundException>()));
    expect(
      repository.save('nope', const ReleaseModel()),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });
}
