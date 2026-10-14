import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('GateConfig', () {
    test('gates every action unless told otherwise', () {
      const config = GateConfig();

      for (final action in GateAction.values) {
        expect(config.isGated(action), isTrue, reason: action.wire);
      }
    });

    test('keeps what it was told', () {
      const config = GateConfig({GateAction.push: false});

      expect(config.isGated(GateAction.push), isFalse);
      expect(config.isGated(GateAction.merge), isTrue);
    });

    test('reads the stored form and ignores what it does not know', () {
      final config = GateConfig.fromJson(const {
        'push': false,
        'merge': 'no',
        'launch_rocket': false,
        'delete': true,
      });

      expect(config.isGated(GateAction.push), isFalse);
      expect(config.isGated(GateAction.merge), isTrue);
      expect(config.isGated(GateAction.delete), isTrue);
    });

    test('writes every action in both forms', () {
      const config = GateConfig({GateAction.push: false});

      final expected = {
        for (final action in GateAction.values)
          action.wire: action != GateAction.push,
      };
      expect(config.toJson(), expected);
      expect(config.toApi(), ProjectGates(expected));
      expect(GateConfig.fromJson(config.toJson()), config);
    });

    test('reads the API form', () {
      final config = GateConfig.fromApi(const ProjectGates({'merge': false}));

      expect(config.isGated(GateAction.merge), isFalse);
      expect(config.isGated(GateAction.prodRelease), isTrue);
    });

    test('refuses an action that is not a gate', () {
      expect(
        () => GateConfig.fromApi(const ProjectGates({'launch_rocket': true})),
        throwsA(
          isA<ApprovalRequestException>().having(
            (error) => error.message,
            'message',
            allOf(contains('"launch_rocket" is not a gate'), contains('push')),
          ),
        ),
      );
    });

    test('tells what moving to another configuration loosens', () {
      const open = GateConfig({GateAction.push: false});
      const tight = GateConfig();
      const looser = GateConfig({
        GateAction.push: false,
        GateAction.merge: false,
      });

      expect(tight.loosenedBy(open), [GateAction.push]);
      expect(tight.loosenedBy(looser), [GateAction.push, GateAction.merge]);
      expect(open.loosenedBy(tight), isEmpty);
      expect(open.loosenedBy(open), isEmpty);
    });

    test('compares by what is gated, not how it was written', () {
      expect(const GateConfig(), GateConfig.fromJson(const {}));
      expect(
        const GateConfig({GateAction.push: true}),
        GateConfig.fromJson(const {}),
      );
      expect(
        const GateConfig({GateAction.push: false}),
        isNot(const GateConfig()),
      );
    });
  });

  group('InMemoryGateConfigRepository', () {
    test('has every gate on until one is set', () async {
      final repository = InMemoryGateConfigRepository();

      expect(await repository.get('prj_1'), const GateConfig());

      await repository.set('prj_1', const GateConfig({GateAction.push: false}));

      expect(
        await repository.get('prj_1'),
        const GateConfig({GateAction.push: false}),
      );
      expect(await repository.get('prj_2'), const GateConfig());
    });
  });
}
