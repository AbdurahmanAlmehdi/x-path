import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/engines/bloc/add_engine_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late MockEnginesRepository engines;

  setUp(() => engines = MockEnginesRepository());

  const submitted = AddEngineSubmitted(
    name: 'mac-mini',
    url: 'mac-mini:7480',
    token: ' xpt_1 ',
  );

  group('AddEngineBloc', () {
    blocTest<AddEngineBloc, AddEngineState>(
      'checks and adds the engine',
      build: () => AddEngineBloc(engines: engines),
      setUp: () => when(
        () => engines.addRemote(
          name: 'mac-mini',
          url: 'mac-mini:7480',
          token: 'xpt_1',
        ),
      ).thenAnswer((_) async => macMini),
      act: (bloc) => bloc.add(submitted),
      expect: () => [
        const AddEngineState(status: AddEngineStatus.checking),
        AddEngineState(status: AddEngineStatus.added, engine: macMini),
      ],
    );

    blocTest<AddEngineBloc, AddEngineState>(
      'says why the engine was refused',
      build: () => AddEngineBloc(engines: engines),
      setUp: () => when(
        () => engines.addRemote(
          name: any(named: 'name'),
          url: any(named: 'url'),
          token: any(named: 'token'),
        ),
      ).thenThrow(const EngineCheckException(EngineCheckFailure.tokenRejected)),
      act: (bloc) => bloc.add(submitted),
      expect: () => [
        const AddEngineState(status: AddEngineStatus.checking),
        const AddEngineState(
          status: AddEngineStatus.failed,
          failure: EngineCheckFailure.tokenRejected,
        ),
      ],
    );

    test('the event compares by value', () {
      expect(submitted.props, ['mac-mini', 'mac-mini:7480', ' xpt_1 ']);
    });
  });
}
