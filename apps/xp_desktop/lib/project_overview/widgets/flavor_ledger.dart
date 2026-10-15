import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart';
import 'package:xp_desktop/project_overview/widgets/release_rail.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The ledger of one app (1A): a row per flavor reading local → testing →
/// live in each store, then its credentials.
class FlavorLedger extends StatelessWidget {
  const new({
    required this.app,
    required this.baseBranch,
    required this.releases,
    required this.credentials,
    this.filter,
    this.onScan,
    super.key,
  });

  final AppProfile app;

  /// The branch the local version is read on.
  final String baseBranch;

  /// The releases of the project, newest first.
  final List<Release> releases;
  final List<Credential> credentials;

  /// The flavor to show alone, if any.
  final String? filter;

  /// Shows the scan of the project; `null` hides the button.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final flavors = [
      for (final flavor in app.flavors)
        if (filter == null || flavor.name == filter) flavor,
    ];
    final columns = [
      l10n.ledgerFlavor,
      l10n.ledgerLocal(baseBranch),
      l10n.ledgerTesting,
      l10n.ledgerLive(l10n.storeAppStore),
      l10n.ledgerLive(l10n.storeGooglePlay),
      l10n.ledgerCredentials,
    ];
    return XpPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                Text(
                  app.name,
                  style: type.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.scanAppMeta(
                            app.path,
                            app.flutterVersion ?? l10n.scanUnpinned,
                            app.storeCountry.toUpperCase(),
                          ),
                          overflow: TextOverflow.ellipsis,
                          style: type.code.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (app.hasIos)
                        _PlatformChip(
                          PhosphorIconsRegular.appleLogo,
                          l10n.platformIos,
                        ),
                      if (app.hasAndroid)
                        _PlatformChip(
                          PhosphorIconsRegular.androidLogo,
                          l10n.platformAndroid,
                        ),
                    ],
                  ),
                ),
                if (onScan case final onScan?)
                  XpButton(
                    label: l10n.overviewScan,
                    icon: PhosphorIconsRegular.magnifyingGlass,
                    kind: XpButtonKind.tertiary,
                    size: XpButtonSize.small,
                    onPressed: onScan,
                  ),
              ],
            ),
          ),
          const XpHairline(),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.3),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(1.2),
              5: FixedColumnWidth(120),
            },
            children: [
              TableRow(
                children: [
                  for (final column in columns)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      child: XpSectionLabel(column),
                    ),
                ],
              ),
              for (final flavor in flavors) _row(context, flavor),
            ],
          ),
          if (flavors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.ledgerNoFlavors,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  TableRow _row(BuildContext context, FlavorProfile flavor) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final mine = [
      for (final release in releases)
        if (release.app == app.path && release.flavor == flavor.name) release,
    ];
    final inFlight = mine
        .where((release) => inFlightStates.contains(release.state))
        .firstOrNull;
    return TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      children: [
        _Cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                flavor.name,
                style: type.titleSm.copyWith(color: colors.textPrimary),
              ),
              Text(
                {?flavor.iosBundleId, ?flavor.androidAppId}.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: type.code.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        _Cell(
          app.version == null
              ? _Value.none(l10n.ledgerNoVersion, l10n.ledgerPubspec)
              : _Value(pubspecLabel(app.version!), Text(l10n.ledgerPubspec)),
        ),
        _Cell(_testing(context, mine, inFlight)),
        _Cell(_live(context, ReleaseStore.apple, mine, inFlight, flavor)),
        _Cell(_live(context, ReleaseStore.play, mine, inFlight, flavor)),
        _Cell(_credentials(context, flavor)),
      ],
    );
  }

  Widget _testing(BuildContext context, List<Release> mine, Release? inFlight) {
    final l10n = context.l10n;
    if (inFlight == null) {
      return mine.isEmpty
          ? _Value.none(l10n.ledgerNoRelease, l10n.ledgerNoReleaseHint)
          : _Value.none(l10n.ledgerUpToDate, l10n.ledgerNothingNewer);
    }
    final version = versionLabel(inFlight.version, inFlight.build);
    final status = releaseStatus(inFlight.state);
    if (inFlight.state == ReleaseState.draft ||
        inFlight.state == ReleaseState.building) {
      return _Value(
        l10n.ledgerNotUploaded,
        XpStatusLabel(status, l10n.ledgerWaitsFor(version)),
        none: true,
      );
    }
    return _Value(
      version,
      XpStatusLabel(status, l10n.releaseState(inFlight.state)),
    );
  }

  Widget _live(
    BuildContext context,
    ReleaseStore store,
    List<Release> mine,
    Release? inFlight,
    FlavorProfile flavor,
  ) {
    final l10n = context.l10n;
    final live = liveIn(mine, store);
    final pending = inFlight == null ? null : storeOf(inFlight, store);
    final next = pending == null || pending.state == StoreState.live
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                inFlight!.version,
                style: context.xpType.code.copyWith(
                  color: context.xpColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: XpStatusLabel(
                  storeStatus(store, pending.state),
                  l10n.storeState(store, pending.state),
                ),
              ),
            ],
          );
    final current = live == null
        ? _Value.none(
            l10n.ledgerNotOnStore,
            flavor.prod ? l10n.ledgerNoLiveRelease : l10n.ledgerNotProd,
          )
        : _Value(
            live.version,
            XpStatusLabel(
              storeStatus(store, StoreState.live),
              l10n.storeState(store, StoreState.live),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        current,
        if (next != null) ...[const SizedBox(height: 4), next],
      ],
    );
  }

  Widget _credentials(BuildContext context, FlavorProfile flavor) {
    final l10n = context.l10n;
    final mine = [
      for (final credential in credentials)
        if (credential.app == app.path && credential.flavor == flavor.name)
          credential.status,
    ];
    final (status, label) = mine.isEmpty
        ? (XpStatus.credentialMissing, l10n.ledgerCredentialsNone)
        : mine.contains(CredentialStatus.rejected)
        ? (XpStatus.credentialExpired, l10n.credentialRejected)
        : mine.every((status) => status == CredentialStatus.verified)
        ? (XpStatus.credentialVerified, l10n.credentialVerified)
        : (XpStatus.credentialExpiring, l10n.credentialUnchecked);
    return XpStatusLabel(status, label);
  }
}

class _Cell extends StatelessWidget {
  const new(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 12, 10), child: child);
}

/// A ledger value: the version in `type.code-lg` (or a quiet word when
/// there is none) over a line that says where it comes from.
class _Value extends StatelessWidget {
  const new(this.value, this.detail, {this.none = false});

  factory none(String value, String detail) =>
      _Value(value, Text(detail), none: true);

  final String value;
  final Widget detail;
  final bool none;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: none
              ? context.xpType.body.copyWith(color: colors.textSecondary)
              : context.xpType.codeLg.copyWith(color: colors.textPrimary),
        ),
        DefaultTextStyle.merge(
          style: context.xpType.caption.copyWith(color: colors.textSecondary),
          child: detail,
        ),
      ],
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const new(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(context.xpRadii.sm),
      border: Border.all(color: context.xpColors.borderDefault),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: context.xpSizes.iconXs,
          color: context.xpColors.textPrimary,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.xpType.caption.copyWith(
            color: context.xpColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}
