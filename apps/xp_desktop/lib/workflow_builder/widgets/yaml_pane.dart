import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_builder_bloc.dart';
import 'package:xp_desktop/workflow_builder/widgets/yaml_highlighter.dart';

/// The YAML view of the workflow: the document in `color.code.*` on
/// `color.code.surface` with a line-number gutter, each line with an issue
/// marked in the gutter and underlined; under it the issues, which jump to
/// their line.
class YamlPane extends StatefulWidget {
  const new({
    required this.yaml,
    required this.issues,
    required this.validation,
    required this.onChanged,
    super.key,
  });

  final String yaml;
  final List<WorkflowIssue> issues;
  final WorkflowValidation validation;
  final ValueChanged<String> onChanged;

  @override
  State<YamlPane> createState() => _YamlPaneState();
}

class _YamlPaneState extends State<YamlPane> {
  late final _controller = YamlEditingController(text: widget.yaml)
    ..issues = widget.issues;
  final _focus = FocusNode(debugLabel: 'yaml');

  @override
  void didUpdateWidget(YamlPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.yaml != _controller.text) {
      final offset = math.min(
        _controller.selection.baseOffset,
        widget.yaml.length,
      );
      _controller.value = TextEditingValue(
        text: widget.yaml,
        selection: TextSelection.collapsed(offset: math.max(offset, 0)),
      );
    }
    _controller.issues = widget.issues;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Puts the caret at [issue]'s place.
  void _jumpTo(WorkflowIssue issue) {
    final lines = _controller.text.split('\n');
    var offset = 0;
    for (var i = 0; i < issue.line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    final line = issue.line - 1 < lines.length ? lines[issue.line - 1] : '';
    offset += math.min(issue.column - 1, line.length);
    _focus.requestFocus();
    _controller.selection = TextSelection.collapsed(
      offset: math.min(offset, _controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return ColoredBox(
      color: colors.codeSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(validation: widget.validation, issues: widget.issues.length),
          const XpHairline(),
          Expanded(
            child: _Editor(
              controller: _controller,
              focusNode: _focus,
              issues: widget.issues,
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.issues.isNotEmpty) ...[
            const XpHairline(),
            _IssueList(issues: widget.issues, onTap: _jumpTo),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new({required this.validation, required this.issues});

  final WorkflowValidation validation;
  final int issues;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = switch (validation) {
      WorkflowValidation.idle => null,
      WorkflowValidation.checking => XpStatusLabel(
        XpStatus.jobRunning,
        l10n.workflowsChecking,
      ),
      WorkflowValidation.valid when issues == 0 => XpStatusLabel(
        XpStatus.jobSucceeded,
        l10n.workflowsValid,
      ),
      WorkflowValidation.unavailable when issues == 0 => XpStatusLabel(
        XpStatus.scanWarning,
        l10n.workflowsUnchecked,
      ),
      _ => XpStatusLabel(XpStatus.scanError, l10n.workflowsIssues(issues)),
    };
    return Container(
      height: context.xpSizes.rowDefault,
      color: context.xpColors.surfaceBase,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [XpSectionLabel(l10n.workflowsYaml), const Spacer(), ?status],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.issues,
    required this.onChanged,
  });

  final YamlEditingController controller;
  final FocusNode focusNode;
  final List<WorkflowIssue> issues;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final mono = context.xpType.mono;
    final strut = StrutStyle.fromTextStyle(mono, forceStrutHeight: true);
    final style = mono.copyWith(color: colors.codeText);
    final lineHeight = (mono.fontSize ?? 12.5) * (mono.height ?? 1);
    final errorLines = {for (final issue in issues) issue.line};
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) {
          final lines = value.text.split('\n');
          final longest = lines.fold(0, (n, line) => math.max(n, line.length));
          final painter = TextPainter(
            text: TextSpan(text: 'M' * longest, style: style),
            textDirection: TextDirection.ltr,
          )..layout();
          final gutter = 16 + 8.0 * '${lines.length}'.length + 14;
          final width = math.max(
            painter.width + 32,
            constraints.maxWidth - gutter,
          );
          painter.dispose();
          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: gutter,
                  color: colors.codeGutter,
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var line = 1; line <= lines.length; line++)
                        SizedBox(
                          height: lineHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                child: errorLines.contains(line)
                                    ? Icon(
                                        PhosphorIconsFill.xCircle,
                                        size: context.xpSizes.iconXs,
                                        color: colors.codeError,
                                      )
                                    : null,
                              ),
                              Expanded(
                                child: Text(
                                  '$line',
                                  textAlign: TextAlign.right,
                                  strutStyle: strut,
                                  style: style.copyWith(
                                    color: errorLines.contains(line)
                                        ? colors.codeError
                                        : colors.codeComment,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        maxLines: null,
                        style: style,
                        strutStyle: strut,
                        cursorColor: colors.accentDefault,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(12, 8, 16, 8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IssueList extends StatelessWidget {
  const new({required this.issues, required this.onTap});

  final List<WorkflowIssue> issues;
  final ValueChanged<WorkflowIssue> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: ColoredBox(
        color: colors.surfaceRaised,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: XpSectionLabel(context.l10n.workflowsIssuesLabel),
            ),
            for (final issue in issues)
              InkWell(
                onTap: () => onTap(issue),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          PhosphorIconsRegular.xCircle,
                          size: context.xpSizes.iconSm,
                          color: colors.statusNegativeOnContainer,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${issue.line}:${issue.column}',
                          style: type.code.copyWith(
                            color: colors.textSecondary,
                            height: 20 / 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          issue.message,
                          style: type.body.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
