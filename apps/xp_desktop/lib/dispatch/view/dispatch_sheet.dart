import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/dispatch/bloc/dispatch_bloc.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Opens the Dispatch sheet (`Dispatch-Sheet.dc.html`) for [project]. Gives
/// the run dispatched, or `null` when the sheet was closed.
Future<Run?> showDispatchSheet(BuildContext context, Project project) {
  final workflows = context.read<WorkflowsRepository>();
  return showDialog<Run>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) => BlocProvider(
      create: (_) =>
          DispatchBloc(workflows: workflows, project: project)
            ..add(const DispatchStarted()),
      child: const DispatchSheet(),
    ),
  );
}

/// Dispatches for [project] (⌘N, the Dispatch… buttons): opens the sheet
/// while the engine takes commands, then the job view of the run.
Future<void> dispatchFor(BuildContext context, Project project) async {
  if (!context.read<EngineConnectionBloc>().state.status.canCommand) return;
  final shell = context.read<ShellCubit>();
  final run = await showDispatchSheet(context, project);
  if (run != null) shell.show(JobDestination(run.id, projectId: project.id));
}

/// The sheet: workflow, flavors, platforms, ref and version, what will run
/// where and which gates it hits, and "Dispatch N jobs ⌘↩". Return never
/// dispatches.
class DispatchSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<DispatchBloc>().state;
    final bloc = context.read<DispatchBloc>();
    final canCommand = context.canCommand;
    void dispatch() {
      if (canCommand) bloc.add(const DispatchSubmitted());
    }

    final count = state.preview?.jobCount ?? 0;
    return BlocListener<DispatchBloc, DispatchState>(
      listenWhen: (previous, current) => current.run != previous.run,
      listener: (context, state) => Navigator.of(context).pop(state.run),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): dispatch,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Shortcuts(
          // Return never dispatches, not even with the button focused.
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter):
                DoNothingAndStopPropagationIntent(),
          },
          child: Focus(
            autofocus: true,
            child: Dialog(
              alignment: Alignment.topCenter,
              insetPadding: const EdgeInsets.only(top: 36),
              backgroundColor: colors.surfaceOverlay,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.xpRadii.lg),
                side: BorderSide(color: colors.borderStrong),
              ),
              child: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(state),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: _Form(state),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.borderDefault),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.dispatchReturnHint,
                              style: context.xpType.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          XpButton(
                            label: l10n.dispatchCancel,
                            size: XpButtonSize.large,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          XpButton(
                            label: l10n.dispatchButton(count),
                            hint: '⌘↩',
                            kind: XpButtonKind.primary,
                            size: XpButtonSize.large,
                            busy: state.status == DispatchStatus.submitting,
                            tooltip: canCommand ? null : l10n.readOnlyHint,
                            onPressed: state.canDispatch && canCommand
                                ? dispatch
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new(this.state);

  final DispatchState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final app = state.project.profile.apps
        .where((app) => app.path == state.app)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            context.l10n.dispatchTitle,
            style: context.xpType.headline.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              [state.project.fullName.split('/').last, ?app?.name].join(' · '),
              overflow: TextOverflow.ellipsis,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const new(this.state);

  final DispatchState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bloc = context.read<DispatchBloc>();
    final apps = state.project.profile.apps;
    final app = apps.where((app) => app.path == state.app).firstOrNull;
    final workflows = state.workflows;
    final workflow = state.workflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error case final error?) ...[
          XpMessage(XpStatus.scanError, error),
          const SizedBox(height: 12),
        ],
        _Field(
          label: l10n.dispatchWorkflow,
          child: workflows.isEmpty
              ? Text(
                  state.status == DispatchStatus.loading
                      ? ''
                      : l10n.dispatchNoWorkflows,
                  style: context.xpType.body.copyWith(
                    color: context.xpColors.textSecondary,
                  ),
                )
              : Row(
                  children: [
                    Flexible(
                      child: XpSelect<String>(
                        value: workflow?.id ?? workflows.first.id,
                        values: [for (final item in workflows) item.id],
                        labelOf: (id) =>
                            workflows.firstWhere((item) => item.id == id).name,
                        onChanged: (id) =>
                            bloc.add(DispatchWorkflowChanged(id)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      [
                        if (workflow?.builtin ?? false) l10n.dispatchBuiltin,
                        if (state.preview?.gates.isNotEmpty ?? false)
                          l10n.dispatchGated,
                      ].join(' · '),
                      style: context.xpType.code.copyWith(
                        color: context.xpColors.textTertiary,
                      ),
                    ),
                  ],
                ),
        ),
        if (apps.length > 1) ...[
          const SizedBox(height: 16),
          _Field(
            label: l10n.dispatchApp,
            child: Align(
              alignment: Alignment.centerLeft,
              child: XpSelect<String>(
                value: state.app,
                values: [for (final app in apps) app.path],
                labelOf: (path) =>
                    apps.firstWhere((app) => app.path == path).name,
                onChanged: (path) => bloc.add(DispatchAppChanged(path)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                label: l10n.dispatchFlavors,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final flavor
                        in app?.flavors ?? const <FlavorProfile>[])
                      XpChip(
                        label: flavor.name,
                        selected: state.chosenFlavors.contains(flavor.name),
                        onChanged: (_) =>
                            bloc.add(DispatchFlavorToggled(flavor.name)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Field(
                label: l10n.dispatchPlatforms,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (app?.hasIos ?? false)
                      XpChip(
                        label: l10n.platformIos,
                        icon: PhosphorIconsRegular.appleLogo,
                        selected: state.chosenPlatforms.contains('ios'),
                        onChanged: (_) =>
                            bloc.add(const DispatchPlatformToggled('ios')),
                      ),
                    if (app?.hasAndroid ?? false)
                      XpChip(
                        label: l10n.platformAndroid,
                        icon: PhosphorIconsRegular.androidLogo,
                        selected: state.chosenPlatforms.contains('android'),
                        onChanged: (_) =>
                            bloc.add(const DispatchPlatformToggled('android')),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Field(
          label: l10n.dispatchRef,
          child: Row(
            children: [
              XpSegmented<RefKind>(
                value: state.refKind,
                values: RefKind.values,
                labelOf: (kind) => switch (kind) {
                  RefKind.branch => l10n.dispatchBranch,
                  RefKind.tag => l10n.dispatchTag,
                },
                onChanged: (kind) => bloc.add(DispatchRefKindChanged(kind)),
              ),
              const SizedBox(width: 8),
              Expanded(child: _RefField(initial: state.ref)),
            ],
          ),
        ),
        if (state.bumps) ...[
          const SizedBox(height: 16),
          _Field(
            label: l10n.dispatchVersion,
            child: Row(
              children: [
                XpSegmented<VersionBump>(
                  value: state.bump,
                  values: const [
                    VersionBump.keep,
                    VersionBump.patch,
                    VersionBump.minor,
                    VersionBump.major,
                  ],
                  labelOf: (bump) => switch (bump) {
                    VersionBump.keep => l10n.bumpKeep,
                    VersionBump.patch => l10n.bumpPatch,
                    VersionBump.minor => l10n.bumpMinor,
                    VersionBump.major => l10n.bumpMajor,
                  },
                  onChanged: (bump) => bloc.add(DispatchBumpChanged(bump)),
                ),
                const SizedBox(width: 12),
                if (state.preview?.version case final version?) ...[
                  Text(
                    version,
                    style: context.xpType.code.copyWith(
                      color: context.xpColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (state.preview?.currentVersion case final current?)
                  Flexible(
                    child: Text(
                      l10n.dispatchFromPubspec(pubspecLabel(current)),
                      overflow: TextOverflow.ellipsis,
                      style: context.xpType.caption.copyWith(
                        color: context.xpColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (state.preview case final preview?) _WillRun(preview),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [XpSectionLabel(label), const SizedBox(height: 6), child],
  );
}

class _RefField extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_RefField> createState() => _RefFieldState();
}

class _RefFieldState extends State<_RefField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.xpRadii.md),
      borderSide: BorderSide(color: colors.borderDefault),
    );
    return SizedBox(
      height: context.xpSizes.controlMd,
      child: TextField(
        controller: _controller,
        style: context.xpType.code.copyWith(color: colors.textPrimary),
        cursorColor: colors.accentDefault,
        onChanged: (ref) =>
            context.read<DispatchBloc>().add(DispatchRefChanged(ref)),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceSunken,
          prefixIcon: Icon(
            PhosphorIconsRegular.gitBranch,
            size: context.xpSizes.iconSm,
            color: colors.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(
              color: colors.focusRing,
              width: context.xpBorders.widthFocus,
            ),
          ),
        ),
      ),
    );
  }
}

class _WillRun extends StatelessWidget {
  const new(this.preview);

  final DispatchPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final engine = context.engineName;
    final rows = <Widget>[];
    for (final stage in preview.stages) {
      final remote = stage.jobs.where((job) => !job.engineOnly).toList();
      if (remote.isEmpty) {
        rows.add(
          _Row(
            status: XpStatus.jobQueued,
            title: _title(stage.name),
            meta: l10n.dispatchOnEngine(stage.jobs.length, engine),
          ),
        );
      } else {
        for (final job in stage.jobs) {
          rows.add(
            _Row(
              status: job.runner == null
                  ? XpStatus.jobQueued
                  : XpStatus.runnerBusy,
              title: job.name,
              meta: job.engineOnly || job.runner == null
                  ? engine
                  : l10n.dispatchOnRunner(
                      engine,
                      job.runner!.name,
                      job.slot!,
                      job.runner!.slots,
                    ),
            ),
          );
        }
      }
      if (stage.gates.isNotEmpty) {
        rows.add(
          _Row(
            status: XpStatus.approvalPending,
            title: l10n.dispatchGateTitle(_title(stage.name)),
            meta: l10n.dispatchGates(
              stage.gates.map(l10n.gateAction).join(', '),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpSectionLabel(
          l10n.dispatchWillRun(preview.jobCount, preview.stages.length),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text(
            l10n.dispatchNothing,
            style: context.xpType.body.copyWith(
              color: context.xpColors.textSecondary,
            ),
          ),
        ...rows,
      ],
    );
  }

  static String _title(String name) =>
      name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

class _Row extends StatelessWidget {
  const new({required this.status, required this.title, required this.meta});

  final XpStatus status;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            status.icon,
            size: context.xpSizes.iconSm,
            color: colors.onContainer(status.pair),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: context.xpType.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              meta,
              overflow: TextOverflow.ellipsis,
              style: context.xpType.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
