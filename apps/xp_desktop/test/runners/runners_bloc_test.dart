import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/runners/runners.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';

void main() {
  late MockRunnersRepository runners;

  setUp(() => runners = MockRunnersRepository());

  test('events compare by value', () {
    expect(const RunnersSubscriptionRequested().props, isEmpty);
    expect(const RunnerRevokeRequested('rnr_1').props, ['rnr_1']);
    expect(const PairingTokenRequested('mac').props, ['mac']);
  });

  group('RunnersState', () {
    test('splits active and revoked runners and counts the busy ones', () {
      final state = RunnersState(
        runners: [busyRunner, idleRunner, lostRunner, revokedRunner],
      );
      expect(state.active, [busyRunner, idleRunner, lostRunner]);
      expect(state.revoked, [revokedRunner]);
      expect(state.busy, 1);
    });
  });

  group('RunnersBloc', () {
    blocTest<RunnersBloc, RunnersState>(
      'follows the runners and keeps them when the engine refuses',
      setUp: () => when(runners.watchRunners).thenAnswer(
        (_) => Stream.fromIterable([
          Snapshot([busyRunner], cached: true),
          Snapshot([busyRunner, idleRunner]),
        ]).followedBy(const ApiException('Nope.', statusCode: 500)),
      ),
      build: () => RunnersBloc(runners: runners),
      act: (bloc) => bloc.add(const RunnersSubscriptionRequested()),
      expect: () => [
        RunnersState(loaded: true, runners: [busyRunner], cached: true),
        RunnersState(loaded: true, runners: [busyRunner, idleRunner]),
        RunnersState(
          loaded: true,
          runners: [busyRunner, idleRunner],
          error: 'Nope.',
        ),
      ],
    );

    blocTest<RunnersBloc, RunnersState>(
      'revokes a runner',
      setUp: () =>
          when(() => runners.revoke('rnr_1'))
              .thenAnswer((_) async => revokedRunner),
      build: () => RunnersBloc(runners: runners),
      act: (bloc) => bloc.add(const RunnerRevokeRequested('rnr_1')),
      expect: () => const [RunnersState(revoking: 'rnr_1'), RunnersState()],
    );

    blocTest<RunnersBloc, RunnersState>(
      'says why a revoke failed',
      setUp: () =>
          when(() => runners.revoke('rnr_1'))
              .thenThrow(const ApiException('Forbidden.', statusCode: 403)),
      build: () => RunnersBloc(runners: runners),
      act: (bloc) => bloc.add(const RunnerRevokeRequested('rnr_1')),
      expect: () => const [
        RunnersState(revoking: 'rnr_1'),
        RunnersState(error: 'Forbidden.'),
      ],
    );
  });

  group('PairRunnerBloc', () {
    final token = PairingToken(
      token: 'xpp_secret',
      name: 'mac-mini',
      expiresAt: DateTime.utc(2026, 10, 13, 12, 23),
    );

    blocTest<PairRunnerBloc, PairRunnerState>(
      'makes a pairing token for the trimmed name',
      setUp: () =>
          when(() => runners.createPairingToken('mac-mini'))
              .thenAnswer((_) async => token),
      build: () => PairRunnerBloc(runners: runners),
      act: (bloc) => bloc.add(const PairingTokenRequested(' mac-mini ')),
      expect: () => [
        const PairRunnerState(status: PairRunnerStatus.creating),
        PairRunnerState(status: PairRunnerStatus.created, token: token),
      ],
    );

    blocTest<PairRunnerBloc, PairRunnerState>(
      'says why the engine refused',
      setUp: () => when(() => runners.createPairingToken('mac-mini'))
          .thenThrow(const ApiException('The name is taken.', statusCode: 409)),
      build: () => PairRunnerBloc(runners: runners),
      act: (bloc) => bloc.add(const PairingTokenRequested('mac-mini')),
      expect: () => const [
        PairRunnerState(status: PairRunnerStatus.creating),
        PairRunnerState(
          status: PairRunnerStatus.failed,
          error: 'The name is taken.',
        ),
      ],
    );
  });
}

extension on Stream<Snapshot<List<Runner>>> {
  Stream<Snapshot<List<Runner>>> followedBy(Object error) async* {
    yield* this;
    yield* Stream.error(error);
  }
}
