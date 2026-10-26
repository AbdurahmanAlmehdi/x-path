import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Keeps the menus the app sets, instead of sending them to macOS.
class _MenuDelegate extends PlatformMenuDelegate {
  List<PlatformMenuItem> menus = const [];

  @override
  void clearMenus() => menus = const [];

  @override
  void setMenus(List<PlatformMenuItem> topLevelMenus) => menus = topLevelMenus;

  @override
  bool debugLockDelegate(BuildContext context) => true;

  @override
  bool debugUnlockDelegate(BuildContext context) => true;
}

/// Every item of [menus], depth first.
Iterable<PlatformMenuItem> _items(List<PlatformMenuItem> menus) sync* {
  for (final menu in menus) {
    yield menu;
    if (menu is PlatformMenu) yield* _items(menu.menus);
    if (menu is PlatformMenuItemGroup) yield* _items(menu.members);
  }
}

/// The shortcuts the keyboard guide lists, as it writes them.
List<String> _guideShortcuts() {
  final guide = File('../../docs/design/system/project/guide/08-keyboard.md')
      .readAsStringSync();
  return [
    for (final row in RegExp(
      r'^\| (.+?) \| .+ \|$',
      multiLine: true,
    ).allMatches(guide))
      if (row.group(1) case final keys? when keys != 'Shortcut')
        ...keys.split(' / '),
  ];
}

void main() {
  test('every shortcut of the keyboard guide is a command', () {
    final commands = {for (final command in XpCommand.values) command.keys};

    expect(_guideShortcuts(), hasLength(greaterThan(15)));
    for (final keys in _guideShortcuts()) {
      // ⌘1–⌘9 are the projects; ⌘C copies a selected row (U6c).
      if (keys == '⌘1 – ⌘9' || keys == '⌘C') continue;
      expect(commands, contains(keys), reason: keys);
    }
  });

  testWidgets('on macOS every command and project is in a menu', (
    tester,
  ) async {
    final delegate = _MenuDelegate();
    final original = WidgetsBinding.instance.platformMenuDelegate;
    WidgetsBinding.instance.platformMenuDelegate = delegate;
    addTearDown(() => WidgetsBinding.instance.platformMenuDelegate = original);
    final shell = ShellCubit(const ApprovalsDestination());
    await tester.pumpApp(
      const AppMenuBar(child: SizedBox()),
      shell: shell,
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa, captain]),
      ),
    );

    final items = _items(delegate.menus).toList();
    final shortcuts = {
      for (final item in items)
        if (item.shortcut case final SingleActivator shortcut)
          describeActivator(shortcut),
    };
    for (final command in XpCommand.values) {
      expect(shortcuts, contains(command.keys), reason: command.name);
    }
    expect(shortcuts, containsAll(['⌘1', '⌘2']));
    expect(
      items.whereType<PlatformProvidedMenuItem>().map((item) => item.type),
      contains(PlatformProvidedMenuItemType.quit),
    );

    items
        .firstWhere((item) => item.label == 'acme/mataa_captain')
        .onSelected!();
    expect(shell.state, const ProjectDestination('prj_2'));
    expect(
      items.firstWhere((item) => item.label == 'Settings…').onSelected,
      isNotNull,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('elsewhere it is only its child', (tester) async {
    await tester.pumpApp(const AppMenuBar(child: Text('content')));

    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.text('content'), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.text('content')));
    final menus = appMenus(l10n, projects: const [], onProject: (_) {});
    expect(menus.map((menu) => menu.label), [
      'XPath',
      'Go',
      'Project',
      'Job',
      'View',
      'Window',
    ]);
  });
}
