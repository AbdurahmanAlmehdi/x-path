import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/pump_app.dart';

/// Whether live motion runs, and the time live durations are measured to.
class _Readout extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Text(
    'live ${XpClock.isLive(context)} at ${XpClock.now(context) == testNow}',
  );
}

void main() {
  group('EngineStaleness', () {
    late StreamController<EngineConnectionState> statuses;

    setUp(() => statuses = StreamController<EngineConnectionState>());
    tearDown(() => statuses.close());

    Future<void> pump(
      WidgetTester tester, {
      EngineStatus status = EngineStatus.connected,
      bool? cached = false,
    }) async {
      final connection = MockEngineConnectionBloc();
      whenListen(
        connection,
        statuses.stream,
        initialState: connectedTo(status: status),
      );
      await tester.pumpApp(
        ShellPage(title: 'Runs', cached: cached, child: const _Readout()),
        connection: connection,
      );
    }

    Future<void> become(WidgetTester tester, EngineStatus status) async {
      statuses.add(connectedTo(status: status));
      await tester.pump();
      await tester.pump();
    }

    final cachedAt = 'Cached · ${formatTime(testNow)}';

    testWidgets('shows nothing while the engine answers', (tester) async {
      await pump(tester);
      expect(find.textContaining('Cached'), findsNothing);
      expect(find.text('live true at true'), findsOneWidget);
    });

    testWidgets('holds time and says since when while the engine is away', (
      tester,
    ) async {
      await pump(tester);

      await become(tester, EngineStatus.reconnecting);
      expect(find.text(cachedAt), findsOneWidget);
      expect(find.text('live false at true'), findsOneWidget);

      await become(tester, EngineStatus.unreachable);
      expect(find.text(cachedAt), findsOneWidget);

      await become(tester, EngineStatus.connected);
      expect(find.textContaining('Cached'), findsNothing);
      expect(find.text('live true at true'), findsOneWidget);
    });

    testWidgets('leaves the time out when the engine was never heard', (
      tester,
    ) async {
      await pump(tester, status: EngineStatus.connecting);
      await become(tester, EngineStatus.unreachable);
      expect(find.text('Cached'), findsOneWidget);
    });

    testWidgets('a locked engine still answers', (tester) async {
      await pump(tester, status: EngineStatus.secretsLocked);
      expect(find.textContaining('Cached'), findsNothing);
      expect(find.text('live true at true'), findsOneWidget);
    });

    testWidgets('says a cached snapshot is cached while connected', (
      tester,
    ) async {
      await pump(tester, cached: true);
      expect(find.text('Cached'), findsOneWidget);
    });

    testWidgets('a page of nothing of the engine shows no chip', (
      tester,
    ) async {
      await pump(tester, status: EngineStatus.rejected, cached: null);
      expect(find.textContaining('Cached'), findsNothing);
      expect(find.text('live false at true'), findsOneWidget);
    });
  });
}
