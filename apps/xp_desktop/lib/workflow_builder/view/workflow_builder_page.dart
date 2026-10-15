import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_builder_bloc.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_edits.dart';
import 'package:xp_desktop/workflow_builder/widgets/workflow_dialogs.dart';
import 'package:xp_desktop/workflow_builder/widgets/workflow_graph.dart';
import 'package:xp_desktop/workflow_builder/widgets/workflow_inspector.dart';
import 'package:xp_desktop/workflow_builder/widgets/yaml_pane.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The workflows of a project (PRODUCT §6.9): a visual builder and a live
/// YAML view of the same document. Opens [workflowId] if given.
class WorkflowBuilderPage extends StatelessWidget {
  const new({required this.projectId, this.workflowId, super.key});

  final String projectId;
  final String? workflowId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: l10n.workflowsTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.projectGone),
        ),
      );
    }
    final services = context.read<AppServices>();
    return BlocProvider(
      key: ValueKey((projectId, workflowId)),
      create: (context) => WorkflowBuilderBloc(
        workflows: context.read<WorkflowsRepository>(),
        projectId: projectId,
        pickFile: services.pickFile,
        saveFile: services.saveFile,
      )..add(WorkflowBuilderStarted(workflowId: workflowId)),
      child: const WorkflowBuilderView(),
    );
  }
}

class WorkflowBuilderView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<WorkflowBuilderBloc>().state;
    final bloc = context.read<WorkflowBuilderBloc>();
    final canCommand = context.canCommand;
    final busy = state.command != WorkflowCommand.none;
    final workflow = state.workflow;
    final subtitle = [
      ?state.name,
      if (workflow == null)
        l10n.workflowsDraft
      else
        l10n.workflowsVersion(workflow.version.version),
      if (workflow?.builtin ?? false) l10n.workflowsBuiltin,
      if (workflow != null && state.dirty) l10n.workflowsUnsaved,
    ].join(' · ');

    Future<void> leave(VoidCallback then) async {
      if (state.dirty &&
          !await confirmDiscard(context, state.name ?? l10n.workflowsTitle)) {
        return;
      }
      then();
    }

    Future<void> save() async {
      if (!state.savesAsNew) {
        bloc.add(const WorkflowSaveRequested());
        return;
      }
      final name = await askWorkflowName(
        context,
        initial: state.draftName ?? workflow?.name,
      );
      if (name != null) bloc.add(WorkflowSaveRequested(name: name));
    }

    final canSave = canCommand && !busy && state.loaded && state.dirty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (canSave || (canCommand && !busy && state.savesAsNew)) {
            unawaited(save());
          }
        },
      },
      child: ShellPage(
        title: l10n.workflowsTitle,
        subtitle: state.loaded ? subtitle : null,
        actions: [
          if (state.workflows.isNotEmpty)
            Semantics(
              label: l10n.workflowsPick,
              child: XpSelect<String?>(
                value: workflow?.id,
                values: [
                  if (workflow == null) null,
                  if (workflow != null &&
                      !state.workflows.any((w) => w.id == workflow.id))
                    workflow.id,
                  ...state.workflows.map((w) => w.id),
                ],
                labelOf: (id) => switch (id) {
                  null => state.name ?? l10n.workflowsDraft,
                  _ when id == workflow?.id => workflow!.name,
                  _ => state.workflows.firstWhere((w) => w.id == id).name,
                },
                code: true,
                onChanged: busy
                    ? null
                    : (id) {
                        if (id != null && id != workflow?.id) {
                          unawaited(leave(() => bloc.add(WorkflowOpened(id))));
                        }
                      },
              ),
            ),
          XpButton(
            label: l10n.workflowsNew,
            icon: PhosphorIconsRegular.plus,
            onPressed: busy
                ? null
                : () => leave(() => bloc.add(const WorkflowDraftStarted())),
          ),
          XpButton(
            label: l10n.workflowsImport,
            icon: PhosphorIconsRegular.downloadSimple,
            busy: state.command == WorkflowCommand.importing,
            onPressed: busy
                ? null
                : () => leave(() => bloc.add(const WorkflowImportRequested())),
          ),
          XpButton(
            label: l10n.workflowsExport,
            icon: PhosphorIconsRegular.uploadSimple,
            busy: state.command == WorkflowCommand.exporting,
            onPressed: busy || !state.loaded
                ? null
                : () => bloc.add(const WorkflowExportRequested()),
          ),
          XpButton(
            label: state.savesAsNew ? l10n.workflowsSaveAs : l10n.workflowsSave,
            kind: XpButtonKind.primary,
            hint: '⌘S',
            busy: state.command == WorkflowCommand.saving,
            tooltip: canCommand ? null : l10n.readOnlyHint,
            onPressed:
                canCommand &&
                    !busy &&
                    state.loaded &&
                    (state.dirty || state.savesAsNew)
                ? save
                : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._messages(context, state),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: _Visual(state: state)),
                  const XpHairline(vertical: true),
                  Expanded(
                    flex: 4,
                    child: YamlPane(
                      yaml: state.yaml,
                      issues: state.issues,
                      validation: state.validation,
                      onChanged: (yaml) => bloc.add(WorkflowYamlChanged(yaml)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _messages(BuildContext context, WorkflowBuilderState state) {
    final l10n = context.l10n;
    final messages = [
      if (state.error case final error?) XpMessage(XpStatus.scanError, error),
      if (state.notice case final notice?)
        XpMessage(XpStatus.jobSucceeded, switch (notice) {
          WorkflowSavedNotice(:final name, :final version) =>
            l10n.workflowsSaved(name, version),
          WorkflowExportedNotice(:final path) => l10n.workflowsExported(path),
        }),
      if (state.workflow?.builtin ?? false)
        XpMessage(XpStatus.scanInfo, l10n.workflowsBuiltinHint),
    ];
    if (messages.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, message) in messages.indexed) ...[
              if (index > 0) const SizedBox(height: 6),
              message,
            ],
          ],
        ),
      ),
      const SizedBox(height: 4),
    ];
  }
}

/// The visual editor: the pipeline over the inspector of what it selects.
class _Visual extends StatelessWidget {
  const new({required this.state});

  final WorkflowBuilderState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<WorkflowBuilderBloc>();
    final document = state.document;
    if (document == null) {
      return state.shapeIssues.isEmpty
          ? const SizedBox()
          : Padding(
              padding: const EdgeInsets.all(20),
              child: XpMessage(
                XpStatus.scanWarning,
                context.l10n.workflowsShapeLocked,
              ),
            );
    }
    final enabled = state.editable;
    void edit(WorkflowDocument document, [WorkflowSelection? selection]) =>
        bloc.add(WorkflowDocumentEdited(document, selection: selection));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!enabled) ...[
          XpMessage(XpStatus.scanWarning, context.l10n.workflowsShapeLocked),
          const SizedBox(height: 12),
        ],
        WorkflowGraph(
          document: document,
          selection: state.selection,
          enabled: enabled,
          onSelect: (selection) =>
              bloc.add(WorkflowSelectionChanged(selection)),
          onEdit: edit,
        ),
        const SizedBox(height: 16),
        WorkflowInspector(
          document: document,
          selection: state.selection,
          schema: state.schema,
          enabled: enabled,
          onEdit: edit,
        ),
      ],
    );
  }
}
