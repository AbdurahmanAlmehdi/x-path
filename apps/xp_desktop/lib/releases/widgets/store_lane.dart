import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Where a step of a lane is.
enum LanePhase { done, now, todo }

/// One step of a store lane: `Uploaded`, `In review`, `Ready for sale`.
class LaneStep {
  const new(this.label, this.phase, [this.time]);

  final String label;
  final LanePhase phase;
  final String? time;
}

/// The store states the owner may set by hand, once the store has the
/// build (the engine's rule).
const Set<StoreState> _markable = {
  StoreState.uploaded,
  StoreState.inReview,
  StoreState.approved,
};

/// The release states whose rollout can change: the stores approved it.
const Set<ReleaseState> _rolledOut = {
  ReleaseState.approved,
  ReleaseState.live,
  ReleaseState.merged,
};

/// The shares of users, in percent, Google Play's staged rollout offers.
const List<int> _shares = [5, 10, 20, 50];

/// The steps of a lane in [status]. A store the engine reads ([manual] is
/// false) shows its review; one it cannot read shows what it cannot know.
List<LaneStep> laneSteps(
  StoreStatus status, {
  required bool manual,
  required AppLocalizations l10n,
}) {
  final store = status.store;
  final state = status.state;
  final changed = status.changedAt;
  String? since() =>
      changed == null ? null : l10n.laneSince(formatTime(changed));
  String? at() => changed == null ? null : formatDateTime(changed);
  final live = l10n.storeState(store, StoreState.live);
  if (state == StoreState.rejected) {
    return [
      LaneStep(l10n.storeUploaded, LanePhase.done),
      LaneStep(l10n.storeInReview, LanePhase.done),
      LaneStep(l10n.storeState(store, state), LanePhase.now, at()),
    ];
  }
  if (manual) {
    final middle = state == StoreState.approved
        ? l10n.storeApproved
        : l10n.storeUnknown;
    final reached = switch (state) {
      StoreState.pending => -1,
      StoreState.uploaded || StoreState.inReview || StoreState.approved => 1,
      _ => 2,
    };
    final steps = [l10n.storeUploaded, middle, live];
    return [
      for (final (index, label) in steps.indexed)
        LaneStep(
          label,
          index < reached
              ? LanePhase.done
              : index == reached
              ? LanePhase.now
              : LanePhase.todo,
          index != reached
              ? null
              : index == 1 && state != StoreState.approved
              ? (store == ReleaseStore.apple
                    ? l10n.laneNoApiKey
                    : l10n.laneNoServiceAccount)
              : index == 2
              ? at()
              : since(),
        ),
    ];
  }
  final review =
      store == ReleaseStore.apple && status.detail == 'WAITING_FOR_REVIEW'
      ? l10n.storeWaitingForReview
      : l10n.storeInReview;
  final steps = [l10n.storeUploaded, review, l10n.storeApproved, live];
  final reached = switch (state) {
    StoreState.pending => -1,
    StoreState.uploaded => 0,
    StoreState.inReview => 1,
    StoreState.approved => 2,
    _ => 3,
  };
  return [
    for (final (index, label) in steps.indexed)
      LaneStep(
        label,
        index < reached
            ? LanePhase.done
            : index == reached
            ? LanePhase.now
            : LanePhase.todo,
        index != reached ? null : (index == 3 ? at() : since()),
      ),
  ];
}

/// The newest release of the same app and flavor as [release], other than
/// it, that is live in [store].
Release? liveBefore(
  List<Release> releases,
  Release release,
  ReleaseStore store,
) {
  for (final other in releases) {
    if (other.id == release.id ||
        other.app != release.app ||
        other.flavor != release.flavor) {
      continue;
    }
    if (storeOf(other, store)?.state == StoreState.live) return other;
  }
  return null;
}

/// The lane of one store (`Release-A-Lanes.dc.html`): its state, the steps
/// of its review, and what the owner can do there.
class StoreLane extends StatelessWidget {
  const new({required this.release, required this.store, super.key});

  final Release release;
  final ReleaseStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final board = context.watch<ReleaseBoardBloc>().state;
    final status = storeOf(release, store);
    final manual = !board.readsStore(release, store);
    final unknown =
        manual &&
        status != null &&
        (status.state == StoreState.uploaded ||
            status.state == StoreState.inReview);
    final xpStatus = status == null
        ? XpStatus.releaseDraft
        : unknown
        ? (store == ReleaseStore.apple
              ? XpStatus.appstoreUnknown
              : XpStatus.playUnknown)
        : storeStatus(store, status.state);
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.storeName(store),
                style: type.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: 8),
              XpCode(
                versionLabel(release.version, release.build),
                color: colors.textSecondary,
              ),
              const Spacer(),
              if (status != null)
                XpBadge(
                  xpStatus,
                  unknown
                      ? l10n.storeUnknown
                      : l10n.storeState(store, status.state),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (status == null)
            Text(
              l10n.laneNotTargeted(l10n.storeName(store)),
              style: type.body.copyWith(color: colors.textSecondary),
            )
          else ...[
            _Steps(
              steps: laneSteps(status, manual: manual, l10n: l10n),
              status: xpStatus,
            ),
            const SizedBox(height: 14),
            ..._footer(context, board, status, manual: manual),
          ],
        ],
      ),
    );
  }

  List<Widget> _footer(
    BuildContext context,
    ReleaseBoardState board,
    StoreStatus status, {
    required bool manual,
  }) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final canCommand = context.canCommand;
    final bloc = context.read<ReleaseBoardBloc>();
    final busy = board.command != ReleaseCommand.none;
    final caption = type.caption.copyWith(color: colors.textSecondary);
    final widgets = <Widget>[];
    if (status.state == StoreState.rejected &&
        release.state == ReleaseState.rejected) {
      widgets.add(
        Row(
          children: [
            XpButton(
              label: l10n.laneNewBuild,
              kind: XpButtonKind.primary,
              size: XpButtonSize.small,
              busy: board.command == ReleaseCommand.building,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: canCommand && !busy
                  ? () => _confirmNewBuild(context, bloc)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.laneNewBuildCaption(
                  versionLabel(release.version, release.build),
                ),
                style: caption,
              ),
            ),
          ],
        ),
      );
    } else if (release.state == ReleaseState.rejected) {
      widgets.add(
        Text(l10n.laneReplacedToo(release.build.toString()), style: caption),
      );
    } else if (manual &&
        _markable.contains(status.state) &&
        !release.state.isTerminal) {
      widgets
        ..add(
          Row(
            children: [
              if (store == ReleaseStore.apple &&
                  status.state != StoreState.approved) ...[
                XpButton(
                  label: l10n.laneMarkApproved,
                  size: XpButtonSize.small,
                  tooltip: canCommand ? null : l10n.readOnlyHint,
                  onPressed: canCommand && !busy
                      ? () => _mark(context, bloc, StoreState.approved)
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              XpButton(
                label: l10n.laneMarkLive,
                size: XpButtonSize.small,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand && !busy
                    ? () => _mark(context, bloc, StoreState.live)
                    : null,
              ),
              const Spacer(),
              XpButton(
                label: store == ReleaseStore.apple
                    ? l10n.laneAddApiKey
                    : l10n.laneAddServiceAccount,
                kind: XpButtonKind.tertiary,
                size: XpButtonSize.small,
                onPressed: () => _addCredential(context),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          XpMessage(
            XpStatus.credentialMissing,
            [
              if (store == ReleaseStore.apple)
                l10n.laneManualApple
              else
                l10n.laneManualPlay,
              if (status.source == StatusSource.lookup) ?status.detail,
            ].join(' · '),
          ),
        );
    } else if (!manual && status.note != null) {
      widgets.add(XpMessage(XpStatus.scanWarning, status.note!));
    }
    if (!manual &&
        status.state == StoreState.live &&
        _rolledOut.contains(release.state)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      widgets
        ..add(_rollout(context, bloc, enabled: canCommand && !busy))
        ..add(const SizedBox(height: 6))
        ..add(Text(l10n.laneRolloutCaption, style: caption));
    }
    final before = liveBefore(board.releases, release, store);
    if (before != null && release.state != ReleaseState.rejected) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      widgets.add(
        Text(
          status.state == StoreState.live
              ? l10n.laneReplaced(before.version)
              : l10n.laneLiveNow(before.version),
          style: caption,
        ),
      );
    }
    return widgets;
  }

  /// The rollout controls of the store (U7a): Apple's phased release
  /// pauses, resumes or goes to everyone; Google Play's staged rollout takes
  /// a share of users, halts or goes to everyone.
  Widget _rollout(
    BuildContext context,
    ReleaseBoardBloc bloc, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final board = bloc.state;
    final tooltip = context.canCommand ? null : l10n.readOnlyHint;
    VoidCallback? request(RolloutAction action, [double? fraction]) => enabled
        ? () => bloc.add(
            ReleaseBoardRolloutRequested(
              RolloutRequest(
                store: store,
                action: action,
                userFraction: fraction,
              ),
            ),
          )
        : null;
    Widget button(String label, RolloutAction action) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: XpButton(
        label: label,
        size: XpButtonSize.small,
        busy: board.command == ReleaseCommand.rollingOut,
        tooltip: tooltip,
        onPressed: request(action),
      ),
    );
    return Wrap(
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: switch (store) {
        ReleaseStore.apple => [
          button(l10n.lanePause, RolloutAction.pause),
          button(l10n.laneResume, RolloutAction.resume),
          button(l10n.laneReleaseToAll, RolloutAction.complete),
        ],
        ReleaseStore.play => [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: XpMenuButton(
              label: l10n.laneRollOutTo,
              actions: enabled
                  ? [
                      for (final percent in _shares)
                        XpMenuAction(
                          l10n.lanePercent(percent),
                          request(RolloutAction.fraction, percent / 100)!,
                        ),
                    ]
                  : null,
            ),
          ),
          button(l10n.laneHalt, RolloutAction.halt),
          button(l10n.laneReleaseToAll, RolloutAction.complete),
        ],
      },
    );
  }

  /// Asks, then marks the store [state] by hand.
  Future<void> _mark(
    BuildContext context,
    ReleaseBoardBloc bloc,
    StoreState state,
  ) async {
    final l10n = context.l10n;
    final confirmed = await confirmAction(
      context,
      title: l10n.laneMarkTitle(
        versionLabel(release.version, release.build),
        l10n.storeState(store, state),
      ),
      points: [l10n.laneMarkManual, l10n.laneMarkFinal],
      keep: l10n.confirmKeep,
      confirm: state == StoreState.live
          ? l10n.laneMarkLive
          : l10n.laneMarkApproved,
    );
    if (confirmed) bloc.add(ReleaseBoardStoreMarked(store, state));
  }

  /// Opens the credentials of the release's flavor; the credentials page
  /// when the project or its app is not known here.
  Future<void> _addCredential(BuildContext context) async {
    final project = context.read<ProjectsBloc>().state.byId(release.projectId);
    final app = project?.profile.apps
        .where((app) => app.path == release.app)
        .firstOrNull;
    if (project == null || app == null) {
      context.read<ShellCubit>().show(
        CredentialsDestination(release.projectId),
      );
      return;
    }
    await showFlavorCredentialsSheet(
      context,
      project: project,
      target: (app: app.path, appName: app.name, flavor: release.flavor),
    );
  }

  Future<void> _confirmNewBuild(
    BuildContext context,
    ReleaseBoardBloc bloc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (context) => _NewBuildDialog(release: release),
    );
    if (confirmed ?? false) bloc.add(const ReleaseBoardNewBuildRequested());
  }
}

class _Steps extends StatelessWidget {
  const new({required this.steps, required this.status});

  final List<LaneStep> steps;
  final XpStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final ink = colors.onContainer(status.pair);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in steps.indexed)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Dot(step.phase, ink),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: context.xpBorders.widthEmphasis,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: step.phase == LanePhase.done
                              ? ink
                              : colors.borderDefault,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  step.label,
                  style:
                      (step.phase == LanePhase.now
                              ? type.bodyStrong
                              : type.body)
                          .copyWith(
                            color: step.phase == LanePhase.todo
                                ? colors.textSecondary
                                : step.phase == LanePhase.now
                                ? ink
                                : colors.textPrimary,
                          ),
                ),
                Text(
                  step.time ?? '',
                  style: type.code.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const new(this.phase, this.ink);

  final LanePhase phase;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (phase) {
          LanePhase.done => ink,
          LanePhase.now => colors.surfaceRaised,
          LanePhase.todo => colors.surfaceRaised,
        },
        border: Border.all(
          color: phase == LanePhase.todo ? colors.borderStrong : ink,
          width: phase == LanePhase.now ? 3 : 1.5,
        ),
      ),
    );
  }
}

class _NewBuildDialog extends StatelessWidget {
  const new({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return Dialog(
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.newBuildTitle(release.version),
                style: context.xpType.headline.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.newBuildBody(release.build.toString()),
                style: context.xpType.body.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  XpButton(
                    label: l10n.approvalCancel,
                    size: XpButtonSize.large,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  XpButton(
                    label: l10n.newBuildConfirm,
                    kind: XpButtonKind.primary,
                    size: XpButtonSize.large,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
