import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';

void main() {
  group('highlightYaml', () {
    test('colours keys, values, comments and block text', () {
      const source = '''
# A workflow
schema: 1
name: "Dev #1" # quoted
lock: project
stages:
  - name: build
    jobs:
      build:
        steps:
          - kind: command
            if: true
            with:
              run: |-
                echo a: b

                echo c
              ratio: 0.5
              keep: ~
          -
          - plain
          - 'quoted'
''';
      final lines = highlightYaml(source);

      expect(
        lines.map((runs) => runs.map((run) => run.$1).join()).join('\n'),
        source,
      );
      expect(lines[0], [('# A workflow', YamlToken.comment)]);
      expect(lines[1], [
        ('schema', YamlToken.key),
        (':', YamlToken.text),
        (' ', YamlToken.text),
        ('1', YamlToken.number),
      ]);
      expect(lines[2].sublist(3), [
        ('"Dev #1" ', YamlToken.string),
        ('# quoted', YamlToken.comment),
      ]);
      expect(lines[5].first, ('  - ', YamlToken.text));
      expect(lines[10].last, ('true', YamlToken.keyword));
      expect(lines[12].last, ('|-', YamlToken.keyword));
      expect(lines[13], [('                echo a: b', YamlToken.string)]);
      expect(lines[14], isEmpty);
      expect(lines[16][1], ('ratio', YamlToken.key));
      expect(lines[16].last, ('0.5', YamlToken.number));
      expect(lines[17].last, ('~', YamlToken.keyword));
      expect(lines[18], [('          -', YamlToken.text)]);
      expect(lines[19], [
        ('          - ', YamlToken.text),
        ('plain', YamlToken.text),
      ]);
      expect(lines[20].last, ("'quoted'", YamlToken.string));
    });

    test('keeps a value with only spaces and a comment after a value', () {
      expect(highlightYaml('a:   '), [
        [('a', YamlToken.key), (':', YamlToken.text), ('   ', YamlToken.text)],
      ]);
      expect(highlightYaml('a: # c').single.last, ('# c', YamlToken.comment));
      expect(highlightYaml("a: 'x # y'").single.last, (
        "'x # y'",
        YamlToken.string,
      ));
    });
  });

  testWidgets('the controller underlines each line with an issue', (
    tester,
  ) async {
    final controller = YamlEditingController(text: 'a: 12\nbb: two\nc: 3')
      ..issues = const [
        WorkflowIssue(line: 2, column: 5, message: 'x'),
        WorkflowIssue(line: 2, column: 1, message: 'y'),
        WorkflowIssue(line: 3, column: 1, message: 'z'),
      ];
    addTearDown(controller.dispose);
    var notified = 0;
    controller
      ..addListener(() => notified++)
      ..issues = controller.issues;
    expect(notified, 0);

    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(span.toPlainText(), controller.text);
    final runs = span.children!.cast<TextSpan>();
    bool wavy(TextSpan run) =>
        run.style?.decorationStyle == TextDecorationStyle.wavy;
    expect(runs.where(wavy).map((run) => run.text).join(), 'bb: twoc: 3');
    expect(
      runs.where((run) => !wavy(run)).map((run) => run.text).join(),
      'a: 12\n\n',
    );
    expect(
      runs.firstWhere((run) => run.text == 'a').style?.color,
      XpColors.light.codeKey,
    );

    controller.issues = const [WorkflowIssue(line: 1, column: 5, message: 'x')];
    expect(notified, 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final first = span.children!.cast<TextSpan>().take(5).toList();
    expect(first.map((run) => (run.text, wavy(run))), [
      ('a', false),
      (':', false),
      (' ', false),
      ('1', false),
      ('2', true),
    ]);
  });
}
