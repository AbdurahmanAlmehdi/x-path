import 'dart:async';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';

/// A socket whose closing the test drives.
class _Channel implements WebSocketChannel {
  final _sink = _Sink();

  @override
  WebSocketSink get sink => _sink;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  final _done = Completer<void>();
  int? closeCode;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ManualClock clock;
  late TokenService tokens;
  late TokenSockets sockets;

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 11, 15, 9));
    tokens = TokenService(
      tokens: InMemoryDeviceTokenRepository(),
      people: InMemoryPersonRepository([testOwner]),
      clock: clock,
    );
    sockets = TokenSockets(tokens: tokens, clock: clock);
    addTearDown(sockets.close);
  });

  test('sweeps only while a socket of a token that expires is open', () async {
    final web = await tokens.issueWeb(personId: testOwner.id);
    final app = await tokens.issue(name: 'app', kind: DeviceTokenKind.app);
    final appSocket = _Channel();
    sockets.track(app.token, appSocket);
    expect(sockets.sweeping, isFalse);

    final first = _Channel();
    final second = _Channel();
    sockets
      ..track(web.token, first)
      ..track(web.token, second);
    expect(sockets.sweeping, isTrue);

    await first.sink.close();
    await Future<void>.delayed(Duration.zero);
    expect(sockets.sweeping, isTrue);
    await second.sink.close();
    await Future<void>.delayed(Duration.zero);
    expect(sockets.sweeping, isFalse);
  });

  test('stops sweeping once the expired sockets are closed', () async {
    final web = await tokens.issueWeb(personId: testOwner.id);
    final channel = _Channel();
    sockets.track(web.token, channel);
    clock.advance(TokenService.webSessionLifetime);

    sockets.sweep();

    expect(channel._sink.closeCode, sessionEndedCloseCode);
    expect(sockets.sweeping, isFalse);
  });

  test('stops sweeping when it closes', () async {
    final web = await tokens.issueWeb(personId: testOwner.id);
    sockets.track(web.token, _Channel());

    await sockets.close();

    expect(sockets.sweeping, isFalse);
  });
}
