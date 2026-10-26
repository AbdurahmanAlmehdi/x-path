import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The commands of the keyboard guide
/// (`docs/design/system/project/guide/08-keyboard.md`) with their shortcuts.
/// The menu bar, the shortcut sheet (⌘/), the command palette and the pages
/// all bind these, so a shortcut does the same wherever it is pressed or
/// chosen. ⌘1–⌘9 (projects in sidebar order) are in the Go menu apart.
enum XpCommand {
  palette(SingleActivator(LogicalKeyboardKey.keyK, meta: true)),
  dispatch(SingleActivator(LogicalKeyboardKey.keyN, meta: true)),
  rerun(SingleActivator(LogicalKeyboardKey.keyR, meta: true)),
  resume(SingleActivator(LogicalKeyboardKey.keyR, meta: true, alt: true)),
  cancel(SingleActivator(LogicalKeyboardKey.period, meta: true)),
  approvals(SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true)),
  back(SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)),
  forward(SingleActivator(LogicalKeyboardKey.bracketRight, meta: true)),
  sidebar(SingleActivator(LogicalKeyboardKey.keyS, meta: true, control: true)),
  console(SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true)),
  find(SingleActivator(LogicalKeyboardKey.keyF, meta: true)),
  findNext(SingleActivator(LogicalKeyboardKey.keyG, meta: true)),
  findPrevious(
    SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true),
  ),
  jumpToError(SingleActivator(LogicalKeyboardKey.keyE, meta: true)),
  followTail(SingleActivator(LogicalKeyboardKey.arrowDown, meta: true)),
  timestamps(SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true)),
  wrap(SingleActivator(LogicalKeyboardKey.keyZ, alt: true)),
  compact(SingleActivator(LogicalKeyboardKey.equal, meta: true, control: true)),
  shortcuts(SingleActivator(LogicalKeyboardKey.slash, meta: true)),
  settings(SingleActivator(LogicalKeyboardKey.comma, meta: true));

  new(this.activator);

  /// Its shortcut.
  final SingleActivator activator;

  /// The shortcut as the guide writes it, for example `⇧⌘A`.
  String get keys => describeActivator(activator);
}

/// [activator] as macOS writes a shortcut: modifiers in the order ⌃⌥⇧⌘,
/// then the key.
String describeActivator(SingleActivator activator) {
  final key = switch (activator.trigger) {
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.enter => '↩',
    LogicalKeyboardKey.bracketLeft => '[',
    LogicalKeyboardKey.bracketRight => ']',
    LogicalKeyboardKey.period => '.',
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.equal => '=',
    final key => key.keyLabel.toUpperCase(),
  };
  return [
    if (activator.control) '⌃',
    if (activator.alt) '⌥',
    if (activator.shift) '⇧',
    if (activator.meta) '⌘',
    key,
  ].join();
}

/// Asks the nearest page or shell that handles [command] to do it.
class XpCommandIntent extends Intent {
  const new(this.command);

  final XpCommand command;
}

/// What [XpCommands] does for each command it handles; `null` handles the
/// command by doing nothing (it is not available here right now).
typedef XpCommandHandlers = Map<XpCommand, VoidCallback?>;

/// Binds the shortcuts of [handlers] around [child] and does them: when
/// the key is pressed with the focus inside, and when the command is chosen
/// in the menu bar or the palette ([runCommand]). A command it does not
/// handle goes on to the next [XpCommands] up the tree, so a page handles
/// its own commands and the shell the rest.
class XpCommands extends StatefulWidget {
  const new({required this.handlers, required this.child, super.key});

  final XpCommandHandlers handlers;
  final Widget child;

  @override
  State<XpCommands> createState() => _XpCommandsState();
}

class _XpCommandsState extends State<XpCommands> {
  /// Every scope on screen, the newest (the deepest page) last.
  static final _mounted = <_XpCommandsState>[];

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: {
      for (final command in widget.handlers.keys)
        command.activator: XpCommandIntent(command),
    },
    child: Actions(
      actions: {XpCommandIntent: _XpCommandAction(this)},
      child: widget.child,
    ),
  );
}

class _XpCommandAction extends Action<XpCommandIntent> {
  new(this._scope);

  final _XpCommandsState _scope;

  @override
  Object? invoke(XpCommandIntent intent) {
    final handlers = _scope.widget.handlers;
    if (handlers.containsKey(intent.command)) {
      handlers[intent.command]?.call();
      return null;
    }
    // The context of the scope is above its Actions: the next scope up.
    return Actions.maybeInvoke(_scope.context, intent);
  }
}

/// Does [command] as the menu bar does: in the newest scope on screen that
/// handles it, unless a dialog covers that scope. Returns whether one did.
bool runCommand(XpCommand command) {
  for (final scope in _XpCommandsState._mounted.reversed) {
    final handlers = scope.widget.handlers;
    if (!handlers.containsKey(command)) continue;
    if (ModalRoute.isCurrentOf(scope.context) == false) return false;
    handlers[command]?.call();
    return true;
  }
  return false;
}
