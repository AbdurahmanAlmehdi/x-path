import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  const tokenName = 'XPath app on MacBook';

  setUpAll(() {
    registerFallbackValue(const LocalEngineChecked());
    registerFallbackValue(const EngineConnectionStarted());
  });

  group('LocalEngineListener', () {
    testWidgets('starts the engine on this Mac on its own when it is '
        'unreachable, and ends the episode when it answers', (tester) async {
      final connection = MockEngineConnectionBloc();
      whenListen(
        connection,
        Stream.fromIterable([
          connectedTo(status: EngineStatus.unreachable),
          connectedTo(status: EngineStatus.reconnecting),
          connectedTo(),
          connectedTo(status: EngineStatus.secretsLocked),
        ]),
        initialState: connectedTo(status: EngineStatus.connecting),
      );
      final local = localEngineIn(const LocalEngineState());

      await tester.pumpApp(
        const LocalEngineListener(child: SizedBox()),
        connection: connection,
        localEngine: local,
      );
      await tester.pump();

      verify(
        () => local.add(
          const LocalEngineStartRequested(
            tokenName: tokenName,
            automatic: true,
          ),
        ),
      ).called(1);
      verify(() => local.add(const LocalEngineReachable())).called(2);
    });

    testWidgets('leaves a remote engine alone', (tester) async {
      final connection = MockEngineConnectionBloc();
      whenListen(
        connection,
        Stream.fromIterable([
          connectedTo(status: EngineStatus.unreachable, active: macMini),
        ]),
        initialState: connectedTo(active: macMini),
      );
      final local = localEngineIn(const LocalEngineState());

      await tester.pumpApp(
        const LocalEngineListener(child: SizedBox()),
        connection: connection,
        localEngine: local,
      );
      await tester.pump();

      verifyNever(() => local.add(any()));
    });

    for (final (renewed, event) in [
      (false, const EngineCheckRequested() as EngineConnectionEvent),
      (true, const EnginesChanged()),
    ]) {
      testWidgets('has the connection ${event.runtimeType} once the engine '
          'started', (tester) async {
        final connection = connectionIn(
          connectedTo(status: EngineStatus.unreachable),
        );
        final local = MockLocalEngineBloc();
        whenListen(
          local,
          Stream.fromIterable([
            const LocalEngineState(progress: LocalEngineProgress.starting),
            LocalEngineState(
              running: true,
              progress: LocalEngineProgress.started,
              tokenRenewed: renewed,
            ),
          ]),
          initialState: const LocalEngineState(),
        );

        await tester.pumpApp(
          const LocalEngineListener(child: SizedBox()),
          connection: connection,
          localEngine: local,
        );
        await tester.pump();

        verify(() => connection.add(event)).called(1);
      });
    }

    testWidgets('does not touch a remote connection once the engine on this '
        'Mac started', (tester) async {
      final connection = connectionIn(connectedTo(active: macMini));
      final local = MockLocalEngineBloc();
      whenListen(
        local,
        Stream.fromIterable([
          const LocalEngineState(
            running: true,
            progress: LocalEngineProgress.started,
          ),
        ]),
        initialState: const LocalEngineState(),
      );

      await tester.pumpApp(
        const LocalEngineListener(child: SizedBox()),
        connection: connection,
        localEngine: local,
      );
      await tester.pump();

      verifyNever(() => connection.add(any()));
    });
  });
}
