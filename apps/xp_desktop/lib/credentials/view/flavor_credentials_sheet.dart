import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/credentials/bloc/project_credentials_bloc.dart';
import 'package:xp_desktop/credentials/cubit/store_ids_cubit.dart';
import 'package:xp_desktop/credentials/widgets/credential_form.dart';
import 'package:xp_desktop/credentials/widgets/credential_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Opens the credentials of the flavor [target] of [project]: for each kind,
/// the credential it uses with what the checks found, and the picker that
/// assigns one (an existing one or a new one, to this flavor or every flavor
/// of the app) or removes it; then the flavor's store ids. [focusStoreIds]
/// puts the cursor in them (a scan finding of a missing id).
Future<void> showFlavorCredentialsSheet(
  BuildContext context, {
  required Project project,
  required FlavorTarget target,
  bool focusStoreIds = false,
}) {
  final projects = context.read<ProjectsRepository>();
  final credentials = context.read<CredentialsRepository>();
  final connection = context.read<EngineConnectionBloc>();
  final services = context.read<AppServices>();
  return showDialog<void>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) => RepositoryProvider.value(
      value: services,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: connection),
          BlocProvider(
            create: (_) => ProjectCredentialsBloc(
              projects: projects,
              credentials: credentials,
            )..add(ProjectCredentialsSubscriptionRequested(project.id)),
          ),
          BlocProvider(
            create: (_) =>
                StoreIdsCubit(projects: projects, projectId: project.id),
          ),
        ],
        child: FlavorCredentialsSheet(
          project: project,
          target: target,
          focusStoreIds: focusStoreIds,
        ),
      ),
    ),
  );
}

class FlavorCredentialsSheet extends StatefulWidget {
  const new({
    required this.project,
    required this.target,
    this.focusStoreIds = false,
    super.key,
  });

  final Project project;
  final FlavorTarget target;
  final bool focusStoreIds;

  @override
  State<FlavorCredentialsSheet> createState() => _FlavorCredentialsSheetState();
}

class _FlavorCredentialsSheetState extends State<FlavorCredentialsSheet> {
  /// The kind whose picker is open.
  CredentialKind? _editing;

  void _edit(CredentialKind? kind) {
    context.read<ProjectCredentialsBloc>().add(
      const ProjectCredentialEditorReset(),
    );
    setState(() => _editing = kind);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final target = widget.target;
    final state = context.watch<ProjectCredentialsBloc>().state;
    final mine = state.of(target.app, target.flavor);
    return BlocListener<ProjectCredentialsBloc, ProjectCredentialsState>(
      listenWhen: (previous, current) =>
          previous.assign != current.assign &&
          current.assign == AssignStatus.done,
      listener: (context, _) => setState(() => _editing = null),
      child: Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.only(top: 36, bottom: 36),
        backgroundColor: colors.surfaceOverlay,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.xpRadii.lg),
          side: BorderSide(color: colors.borderStrong),
        ),
        child: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: XpPageHeader(
                  title: l10n.flavorCredentialsTitle(target.flavor),
                  subtitle: '${widget.project.fullName} · ${target.appName}',
                  actions: [
                    XpButton(
                      label: l10n.overviewClose,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const XpHairline(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.flavorCredentialsHelp,
                        style: type.body.copyWith(color: colors.textSecondary),
                      ),
                      if (state.kept.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        XpMessage(
                          XpStatus.scanInfo,
                          l10n.flavorCredentialsKept(
                            state.kept.length,
                            state.kept.map((kept) => kept.flavor).join(', '),
                          ),
                        ),
                      ],
                      if (state.error case final error?
                          when _editing == null ||
                              state.assign != AssignStatus.failed) ...[
                        const SizedBox(height: 12),
                        XpMessage(XpStatus.scanError, error),
                      ],
                      const SizedBox(height: 8),
                      for (final kind in namedKinds)
                        _KindRow(
                          key: Key('flavorCredentials.${kind.wire}'),
                          project: widget.project,
                          target: target,
                          kind: kind,
                          assigned: mine
                              .where((credential) => credential.kind == kind)
                              .firstOrNull,
                          editing: _editing == kind,
                          onEdit: () => _edit(kind),
                          onCancel: () => _edit(null),
                        ),
                      const SizedBox(height: 16),
                      StoreIdsSection(
                        flavor: flavorOf(widget.project, target),
                        target: target,
                        autofocus: widget.focusStoreIds,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The flavor [target] names in [project], if it still has it.
FlavorProfile? flavorOf(Project project, FlavorTarget target) => project
    .profile
    .apps
    .where((app) => app.path == target.app)
    .expand((app) => app.flavors)
    .where((flavor) => flavor.name == target.flavor)
    .firstOrNull;

/// The store ids of the flavor [target] (UX-03): the Firebase app id of each
/// platform and the App Store Connect app id, which the built-in workflows
/// upload to when a dispatch names none. An empty field removes the id.
class StoreIdsSection extends StatefulWidget {
  const new({
    required this.flavor,
    required this.target,
    this.autofocus = false,
    super.key,
  });

  /// The flavor as the project knows it, for the ids it has now.
  final FlavorProfile? flavor;
  final FlavorTarget target;
  final bool autofocus;

  @override
  State<StoreIdsSection> createState() => _StoreIdsSectionState();
}

class _StoreIdsSectionState extends State<StoreIdsSection> {
  late final _android = TextEditingController(
    text: widget.flavor?.firebaseAppId?['android'] ?? '',
  );
  late final _ios = TextEditingController(
    text: widget.flavor?.firebaseAppId?['ios'] ?? '',
  );
  late final _apple = TextEditingController(
    text: widget.flavor?.appleAppId ?? '',
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _android.dispose();
    _ios.dispose();
    _apple.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<StoreIdsCubit>().state;
    final canCommand = context.canCommand;
    return Column(
      key: const Key('flavorCredentials.storeIds'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpSectionLabel(l10n.flavorStoreIds),
        const SizedBox(height: 4),
        Text(
          l10n.flavorStoreIdsHelp,
          style: context.xpType.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 10),
        XpTextField(
          key: const Key('storeIds.firebaseAndroid'),
          label: l10n.flavorFirebaseAndroid,
          hint: l10n.flavorFirebaseHint('android'),
          controller: _android,
          focusNode: _focus,
          code: true,
        ),
        const SizedBox(height: 8),
        XpTextField(
          key: const Key('storeIds.firebaseIos'),
          label: l10n.flavorFirebaseIos,
          hint: l10n.flavorFirebaseHint('ios'),
          controller: _ios,
          code: true,
        ),
        const SizedBox(height: 8),
        XpTextField(
          key: const Key('storeIds.apple'),
          label: l10n.flavorAppleAppId,
          hint: l10n.flavorAppleAppIdHint,
          controller: _apple,
          code: true,
        ),
        if (state.status == StoreIdsStatus.failed) ...[
          const SizedBox(height: 8),
          XpMessage(XpStatus.scanError, state.error!),
        ],
        if (state.status == StoreIdsStatus.saved) ...[
          const SizedBox(height: 8),
          XpMessage(XpStatus.jobSucceeded, l10n.flavorStoreIdsSaved),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: XpButton(
            label: l10n.flavorStoreIdsSave,
            kind: XpButtonKind.primary,
            busy: state.status == StoreIdsStatus.saving,
            tooltip: canCommand ? null : l10n.readOnlyHint,
            onPressed: canCommand && state.status != StoreIdsStatus.saving
                ? () => context.read<StoreIdsCubit>().save(
                    app: widget.target.app,
                    flavor: widget.target.flavor,
                    firebaseAndroid: _android.text,
                    firebaseIos: _ios.text,
                    appleAppId: _apple.text,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// One kind of the flavor: the credential it uses, or none, and its
/// actions; the picker under it while [editing].
class _KindRow extends StatelessWidget {
  const new({
    required this.project,
    required this.target,
    required this.kind,
    required this.assigned,
    required this.editing,
    required this.onEdit,
    required this.onCancel,
    super.key,
  });

  final Project project;
  final FlavorTarget target;
  final CredentialKind kind;
  final Credential? assigned;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final canCommand = context.canCommand;
    final state = context.watch<ProjectCredentialsBloc>().state;
    final busy = state.busy == kind;
    final assigned = this.assigned;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 210,
                child: Text(
                  credentialKindLabel(l10n, kind),
                  style: type.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              Expanded(
                child: assigned == null
                    ? Text(
                        l10n.flavorCredentialsNotAssigned,
                        style: type.body.copyWith(color: colors.textTertiary),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              assigned.name ?? assigned.id,
                              ?assigned.account,
                            ].join(' · '),
                            style: type.body.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          CredentialStatusView(
                            assigned.status,
                            message: assigned.message,
                            fix: assigned.fix,
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              XpButton(
                label: assigned == null
                    ? l10n.flavorCredentialsAssign
                    : l10n.flavorCredentialsChange,
                size: XpButtonSize.small,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand && !editing && !busy ? onEdit : null,
              ),
              if (assigned != null) ...[
                const SizedBox(width: 6),
                XpButton(
                  label: l10n.flavorCredentialsRemove,
                  size: XpButtonSize.small,
                  kind: XpButtonKind.tertiary,
                  onPressed: canCommand && !busy
                      ? () => context.read<ProjectCredentialsBloc>().add(
                          ProjectCredentialUnassignRequested(
                            app: target.app,
                            flavor: target.flavor,
                            kind: kind,
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 10),
            _AssignEditor(
              project: project,
              target: target,
              kind: kind,
              assigned: assigned,
              onCancel: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// The picker of one kind: which credential (an existing one of the kind,
/// or a new one), for this flavor or every flavor of the app, and whether
/// the other flavors give up theirs.
class _AssignEditor extends StatefulWidget {
  const new({
    required this.project,
    required this.target,
    required this.kind,
    required this.assigned,
    required this.onCancel,
  });

  final Project project;
  final FlavorTarget target;
  final CredentialKind kind;
  final Credential? assigned;
  final VoidCallback onCancel;

  @override
  State<_AssignEditor> createState() => _AssignEditorState();
}

class _AssignEditorState extends State<_AssignEditor> {
  /// The choice that stands for a new credential (a menu cannot choose
  /// `null`).
  static const _newOne = '';

  /// The credential chosen, by id, or [_newOne]; `null` until the owner
  /// chooses.
  String? _choice;
  var _allFlavors = false;
  var _replace = false;

  late final bool _hasSiblings =
      flavorTargets(widget.project)
          .where((target) => target.app == widget.target.app)
          .length >
      1;

  AssignmentScope get _scope => AssignmentScope(
    app: widget.target.app,
    flavor: widget.target.flavor,
    allFlavors: _allFlavors,
    replace: _allFlavors && _replace,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final state = context.watch<ProjectCredentialsBloc>().state;
    final bloc = context.read<ProjectCredentialsBloc>();
    final choices = state.choices(widget.kind);
    final ids = [for (final credential in choices) credential.id];
    final current = widget.assigned?.id;
    final choice = switch (_choice) {
      final chosen? when ids.contains(chosen) => chosen,
      null when ids.contains(current) => current!,
      null => ids.firstOrNull ?? _newOne,
      _ => _newOne,
    };
    final working = state.assign == AssignStatus.working;
    final failed = state.assign == AssignStatus.failed ? state.error : null;
    final kindLabel = credentialKindLabel(l10n, widget.kind);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              XpSectionLabel(l10n.flavorCredentialsCredential),
              const SizedBox(width: 8),
              Flexible(
                child: XpSelect<String>(
                  key: const Key('flavorCredentials.choice'),
                  value: choice,
                  values: [...ids, _newOne],
                  labelOf: (id) {
                    if (id == _newOne) return l10n.flavorCredentialsAddNew;
                    final credential = choices.firstWhere(
                      (credential) => credential.id == id,
                    );
                    return [credential.name, ?credential.account].join(' · ');
                  },
                  onChanged: (id) => setState(() => _choice = id),
                ),
              ),
            ],
          ),
          if (_hasSiblings) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                XpSectionLabel(l10n.flavorCredentialsUseFor),
                XpSegmented<bool>(
                  key: const Key('flavorCredentials.scope'),
                  value: _allFlavors,
                  values: const [false, true],
                  labelOf: (all) => all
                      ? l10n.flavorCredentialsEveryFlavor(widget.target.appName)
                      : l10n.flavorCredentialsThisFlavor,
                  onChanged: (all) => setState(() => _allFlavors = all),
                ),
                XpChip(
                  key: const Key('flavorCredentials.replace'),
                  label: l10n.flavorCredentialsReplace,
                  icon: _allFlavors && _replace
                      ? PhosphorIconsRegular.checkCircle
                      : null,
                  selected: _allFlavors && _replace,
                  onChanged: _allFlavors
                      ? (replace) => setState(() => _replace = replace)
                      : null,
                ),
              ],
            ),
            if (_allFlavors) ...[
              const SizedBox(height: 4),
              Text(
                _replace
                    ? l10n.flavorCredentialsReplaceOn(kindLabel)
                    : l10n.flavorCredentialsReplaceOff(kindLabel),
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
          const SizedBox(height: 12),
          if (choice == _newOne)
            CredentialForm(
              kind: widget.kind,
              lockKind: true,
              saving: working,
              error: failed,
              submitLabel: l10n.flavorCredentialsCreate,
              onCancel: widget.onCancel,
              onCreate: (request) => bloc.add(
                ProjectCredentialCreateRequested(
                  scope: _scope,
                  request: request,
                ),
              ),
            )
          else ...[
            if (failed != null) ...[
              XpMessage(XpStatus.scanError, failed),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                XpButton(
                  label: l10n.credentialFormCancel,
                  kind: XpButtonKind.tertiary,
                  onPressed: widget.onCancel,
                ),
                const SizedBox(width: 8),
                XpButton(
                  label: l10n.flavorCredentialsConfirm,
                  kind: XpButtonKind.primary,
                  busy: working,
                  onPressed: () => bloc.add(
                    ProjectCredentialAssignRequested(
                      scope: _scope,
                      kind: widget.kind,
                      credentialId: choice,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
