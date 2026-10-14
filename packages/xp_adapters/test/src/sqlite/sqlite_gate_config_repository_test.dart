import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late SqliteDatabase database;
  late SqliteGateConfigRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection.execute(
      'INSERT INTO project (id, github_repo_id, remote, default_base_branch) '
      "VALUES ('prj_1', 1, 'a', 'main'), ('prj_2', 2, 'b', 'main')",
    );
    repository = SqliteGateConfigRepository(database);
  });

  test('has every gate on for a project that never set one', () async {
    expect(await repository.get('prj_1'), const GateConfig());
  });

  test('has every gate on for a project that does not exist', () async {
    expect(await repository.get('prj_9'), const GateConfig());
  });

  test('stores the gates in project.gates, per project', () async {
    await repository.set('prj_1', const GateConfig({GateAction.push: false}));

    expect(
      await repository.get('prj_1'),
      const GateConfig({GateAction.push: false}),
    );
    expect(await repository.get('prj_2'), const GateConfig());
    expect(
      database.connection
          .select("SELECT gates FROM project WHERE id = 'prj_1'")
          .single['gates'],
      allOf(contains('"push":false'), contains('"prod_release":true')),
    );
  });

  test('replaces what was stored', () async {
    await repository.set('prj_1', const GateConfig({GateAction.push: false}));
    await repository.set('prj_1', const GateConfig());

    expect(await repository.get('prj_1'), const GateConfig());
  });

  test('reads what the table holds when nobody wrote through it', () async {
    database.connection.execute(
      '''UPDATE project SET gates = '{"merge": false, "other": 1}' ''',
    );

    final config = await repository.get('prj_1');

    expect(config.isGated(GateAction.merge), isFalse);
    expect(config.isGated(GateAction.push), isTrue);
  });
}
