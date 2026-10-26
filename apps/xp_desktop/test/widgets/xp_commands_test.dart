import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/widgets/widgets.dart';

void main() {
  Future<void> press(WidgetTester tester, SingleActivator activator) async {
    final modifiers = [
      if (activator.meta) LogicalKeyboardKey.metaLeft,
      if (activator.shift) LogicalKeyboardKey.shiftLeft,
      if (activator.alt) LogicalKeyboardKey.altLeft,
      if (activator.control) LogicalKeyboardKey.controlLeft,
    ];
    for (final key in modifiers) {
      await tester.sendKeyDownEvent(key);
    }
    await tester.sendKeyEvent(activator.trigger);
    for (final key in modifiers.reversed) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();
  }

  testWidgets('a page does its own commands and the shell the rest', (
    tester,
  ) async {
    final done = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: XpCommands(
          handlers: {
            XpCommand.palette: () => done.add('shell palette'),
            XpCommand.dispatch: () => done.add('shell dispatch'),
          },
          child: XpCommands(
            handlers: {
              XpCommand.dispatch: () => done.add('page dispatch'),
              XpCommand.console: null,
            },
            child: const Focus(autofocus: true, child: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pump();

    await press(tester, XpCommand.dispatch.activator);
    await press(tester, XpCommand.palette.activator);
    await press(tester, XpCommand.console.activator);

    expect(done, ['page dispatch', 'shell palette']);
  });

  testWidgets('runCommand goes to the newest scope that handles it', (
    tester,
  ) async {
    final done = <String>[];
    expect(runCommand(XpCommand.palette), isFalse, reason: 'no scope');
    await tester.pumpWidget(
      MaterialApp(
        home: XpCommands(
          handlers: {XpCommand.palette: () => done.add('shell')},
          child: XpCommands(
            handlers: {
              XpCommand.find: () => done.add('page'),
              XpCommand.wrap: null,
            },
            child: const SizedBox(),
          ),
        ),
      ),
    );

    expect(runCommand(XpCommand.find), isTrue);
    expect(runCommand(XpCommand.palette), isTrue);
    expect(runCommand(XpCommand.wrap), isTrue, reason: 'handled by nothing');
    expect(runCommand(XpCommand.dispatch), isFalse);
    expect(done, ['page', 'shell']);
  });

  test('writes each shortcut as the keyboard guide does', () {
    expect(
      {for (final command in XpCommand.values) command: command.keys},
      {
        XpCommand.palette: '⌘K',
        XpCommand.dispatch: '⌘N',
        XpCommand.rerun: '⌘R',
        XpCommand.resume: '⌥⌘R',
        XpCommand.cancel: '⌘.',
        XpCommand.approvals: '⇧⌘A',
        XpCommand.back: '⌘[',
        XpCommand.forward: '⌘]',
        XpCommand.sidebar: '⌃⌘S',
        XpCommand.console: '⇧⌘C',
        XpCommand.find: '⌘F',
        XpCommand.findNext: '⌘G',
        XpCommand.findPrevious: '⇧⌘G',
        XpCommand.jumpToError: '⌘E',
        XpCommand.followTail: '⌘↓',
        XpCommand.timestamps: '⇧⌘T',
        XpCommand.wrap: '⌥Z',
        XpCommand.compact: '⌃⌘=',
        XpCommand.shortcuts: '⌘/',
        XpCommand.settings: '⌘,',
      },
    );
    expect(
      describeActivator(
        const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true),
      ),
      '⌘↑',
    );
    expect(
      describeActivator(const SingleActivator(LogicalKeyboardKey.enter)),
      '↩',
    );
  });
}
