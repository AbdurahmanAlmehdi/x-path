import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/ansi.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The height of a step header in the log.
const logHeaderExtent = 28.0;

/// The height of one log line (`type.mono`, 12.5/21).
const logLineExtent = 21.0;

/// Whether [line] reads as an error: a line on stderr that says so.
bool isErrorLine(LogLineFrame line) =>
    line.stream == LogStream.stderr &&
    line.text.toLowerCase().contains('error');

/// The log of one job, grouped by step (2A): the log bar (what is shown,
/// filter, jump to error, wrap, timestamps, follow), then a header per step
/// and its lines. Finished steps start collapsed with their line count; the
/// running, failed or interrupted step starts open. A failed job opens at
/// its first error line. A line number copies the line with where it is
/// (`job_…:42`).
class LogView extends StatefulWidget {
  const new({
    required this.steps,
    required this.lines,
    required this.title,
    this.status,
    this.live = false,
    this.jobId,
    super.key,
  });

  /// The job the log is of, for the place a copied line names.
  final String? jobId;

  /// The steps of the job.
  final List<JobStep> steps;

  /// The lines held, in order.
  final List<LogLineFrame> lines;

  /// What the log bar says is shown, for example `Build prod for ios · This
  /// Mac · 6m 12s`.
  final String title;

  /// The status of the job, beside [title].
  final XpStatus? status;

  /// Whether the job runs, so new lines arrive and the last one is the
  /// current row.
  final bool live;

  @override
  State<LogView> createState() => _LogViewState();
}

sealed class _Item {
  const new();
}

final class _Header extends _Item {
  const new(this.ordinal, this.step, this.count, {required this.open});

  final int ordinal;
  final JobStep? step;
  final int count;
  final bool open;
}

final class _Line extends _Item {
  const new(this.line, {required this.error, required this.current});

  final LogLineFrame line;
  final bool error;
  final bool current;
}

class _LogViewState extends State<LogView> {
  final _scroll = ScrollController();
  final _filter = TextEditingController();
  final _filterFocus = FocusNode();
  final _toggled = <int, bool>{};
  var _follow = true;
  var _wrap = false;
  var _timestamps = true;

  /// Whether a failed job's log was opened at its error.
  var _openedAtError = false;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() => _match = -1));
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != _shownCount) _scheduleFollow();
  }

  var _shownCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _scheduleFollow() {
    _shownCount = widget.lines.length;
    _jumpToEnd(3);
  }

  /// Jumps to the tail after the next frame, and again while the list
  /// learns its true length.
  void _jumpToEnd(int tries) {
    if (!_follow || tries == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_follow || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        _scroll.jumpTo(position.maxScrollExtent);
        _jumpToEnd(tries - 1);
      }
    });
  }

  bool _openByDefault(JobStep? step) => switch (step?.state) {
    StepState.running ||
    StepState.failed ||
    StepState.interrupted ||
    StepState.waitingForApproval => true,
    _ => false,
  };

  List<_Item> _items() {
    final query = _filter.text.trim().toLowerCase();
    final byStep = <int, List<LogLineFrame>>{};
    for (final line in widget.lines) {
      (byStep[line.step] ??= []).add(line);
    }
    final steps = {for (final step in widget.steps) step.ordinal: step};
    final ordinals = {...steps.keys, ...byStep.keys}.toList()..sort();
    var anyOpen = ordinals.any(
      (ordinal) => _toggled[ordinal] ?? _openByDefault(steps[ordinal]),
    );
    final last = widget.lines.isEmpty ? null : widget.lines.last;
    final items = <_Item>[];
    for (final ordinal in ordinals.reversed) {
      final lines = byStep[ordinal] ?? const [];
      final shown = query.isEmpty
          ? lines
          : [
              for (final line in lines)
                if (line.text.toLowerCase().contains(query)) line,
            ];
      if (query.isNotEmpty && shown.isEmpty) continue;
      var open =
          query.isNotEmpty ||
          (_toggled[ordinal] ?? _openByDefault(steps[ordinal]));
      if (!anyOpen && lines.isNotEmpty && !_toggled.containsKey(ordinal)) {
        // Nothing runs or failed: the last step that wrote is open.
        open = true;
        anyOpen = true;
      }
      items.insertAll(0, [
        _Header(ordinal, steps[ordinal], lines.length, open: open),
        if (open)
          for (final line in shown)
            _Line(
              line,
              error: isErrorLine(line),
              current: widget.live && identical(line, last),
            ),
      ]);
    }
    return items;
  }

  void _jumpToError(List<_Item> items) {
    var offset = 0.0;
    for (final item in items) {
      if (item is _Line && item.error) {
        setState(() => _follow = false);
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
        return;
      }
      offset += item is _Header ? logHeaderExtent : logLineExtent;
    }
  }

  /// The line of the filter's matches that ⌘G and ⇧⌘G last went to.
  var _match = -1;

  /// ⌘G / ⇧⌘G: scrolls to the next or previous line that matches the
  /// filter (with [by] 1 or -1), round the end.
  void _jumpToMatch(List<_Item> items, int by) {
    if (_filter.text.trim().isEmpty) return;
    final offsets = <double>[];
    var offset = 0.0;
    for (final item in items) {
      if (item is _Line) offsets.add(offset);
      offset += item is _Header ? logHeaderExtent : logLineExtent;
    }
    if (offsets.isEmpty) return;
    _match = (_match + by) % offsets.length;
    setState(() => _follow = false);
    _scroll.jumpTo(offsets[_match].clamp(0, _scroll.position.maxScrollExtent));
  }

  Future<void> _copy(LogLineFrame line) async {
    final place = [?widget.jobId, '${line.seq}'].join(':');
    await Clipboard.setData(ClipboardData(text: '$place  ${line.text}'));
    if (mounted) {
      context.read<ToastCubit>().show(context.l10n.logCopiedLine(line.seq));
    }
  }

  void _setFollow(bool value) {
    setState(() => _follow = value);
    if (value) _scheduleFollow();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final items = _items();
    final hasError = items.any((item) => item is _Line && item.error);
    if (hasError &&
        !_openedAtError &&
        !widget.live &&
        widget.status == XpStatus.jobFailed) {
      _openedAtError = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _jumpToError(_items());
      });
    }
    return XpCommands(
      handlers: {
        XpCommand.find: _filterFocus.requestFocus,
        XpCommand.findNext: () => _jumpToMatch(items, 1),
        XpCommand.findPrevious: () => _jumpToMatch(items, -1),
        XpCommand.jumpToError: () => _jumpToError(items),
        XpCommand.followTail: () => _setFollow(!_follow),
        XpCommand.timestamps: () => setState(() => _timestamps = !_timestamps),
        XpCommand.wrap: () => setState(() => _wrap = !_wrap),
      },
      child: Focus(
        child: ColoredBox(
          color: colors.logSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LogBar(
                title: widget.title,
                status: widget.status,
                filter: _filter,
                filterFocus: _filterFocus,
                onJumpToError: hasError ? () => _jumpToError(items) : null,
                wrap: _wrap,
                onWrap: () => setState(() => _wrap = !_wrap),
                timestamps: _timestamps,
                onTimestamps: () => setState(() => _timestamps = !_timestamps),
                follow: _follow,
                onFollow: () => _setFollow(!_follow),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.logEmpty,
                          style: context.xpType.body.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      )
                    : NotificationListener<UserScrollNotification>(
                        onNotification: (notification) {
                          if (notification.direction ==
                                  ScrollDirection.forward &&
                              _follow) {
                            setState(() => _follow = false);
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: items.length,
                          itemExtentBuilder: _wrap
                              ? null
                              : (index, _) => items[index] is _Header
                                    ? logHeaderExtent
                                    : logLineExtent,
                          itemBuilder: (context, index) =>
                              switch (items[index]) {
                                final _Header header => _HeaderRow(
                                  header,
                                  onTap: () => setState(
                                    () =>
                                        _toggled[header.ordinal] = !header.open,
                                  ),
                                ),
                                final _Line line => _LineRow(
                                  line,
                                  wrap: _wrap,
                                  timestamps: _timestamps,
                                  onCopy: () => _copy(line.line),
                                ),
                              },
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

class _LogBar extends StatelessWidget {
  const new({
    required this.title,
    required this.status,
    required this.filter,
    required this.filterFocus,
    required this.onJumpToError,
    required this.wrap,
    required this.onWrap,
    required this.timestamps,
    required this.onTimestamps,
    required this.follow,
    required this.onFollow,
  });

  final String title;
  final XpStatus? status;
  final TextEditingController filter;
  final FocusNode filterFocus;
  final VoidCallback? onJumpToError;
  final bool wrap;
  final VoidCallback onWrap;
  final bool timestamps;
  final VoidCallback onTimestamps;
  final bool follow;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceBase,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          if (status case final status?) ...[
            XpStatusIcon(status),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: type.bodyStrong.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            height: context.xpSizes.controlSm,
            child: TextField(
              controller: filter,
              focusNode: filterFocus,
              style: type.body.copyWith(color: colors.textPrimary),
              cursorColor: colors.accentDefault,
              decoration: InputDecoration(
                isDense: true,
                hintText: '${l10n.logFilter}  ⌘F',
                hintStyle: type.body.copyWith(color: colors.textTertiary),
                prefixIcon: Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: context.xpSizes.iconSm,
                  color: colors.textSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 28),
                filled: true,
                fillColor: colors.surfaceSunken,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.xpRadii.md),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.xpRadii.md),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (onJumpToError case final jump?) ...[
            XpButton(
              label: l10n.logJumpToError,
              icon: PhosphorIconsRegular.warningCircle,
              hint: '⌘E',
              size: XpButtonSize.small,
              onPressed: jump,
            ),
            const SizedBox(width: 6),
          ],
          _Toggle(
            icon: PhosphorIconsRegular.arrowUDownLeft,
            on: wrap,
            tooltip: '${l10n.logWrap}  ⌥Z',
            onTap: onWrap,
          ),
          _Toggle(
            icon: PhosphorIconsRegular.clock,
            on: timestamps,
            tooltip: '${l10n.logTimestamps}  ⇧⌘T',
            onTap: onTimestamps,
          ),
          const SizedBox(width: 4),
          XpButton(
            label: l10n.logFollow,
            icon: follow
                ? PhosphorIconsFill.arrowLineDown
                : PhosphorIconsRegular.arrowLineDown,
            hint: '⌘↓',
            kind: XpButtonKind.tertiary,
            size: XpButtonSize.small,
            onPressed: onFollow,
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const new({
    required this.icon,
    required this.on,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool on;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: context.xpSizes.controlSm,
            height: context.xpSizes.controlSm,
            decoration: BoxDecoration(
              color: on ? context.xpColors.surfacePressed : Colors.transparent,
              borderRadius: BorderRadius.circular(context.xpRadii.md),
            ),
            child: Icon(
              icon,
              size: context.xpSizes.iconSm,
              color: context.xpColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

class _HeaderRow extends StatelessWidget {
  const new(this.header, {required this.onTap});

  final _Header header;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final step = header.step;
    final ran = elapsed(
      step?.startedAt,
      step?.finishedAt,
      XpClock.now(context),
    );
    return Semantics(
      button: true,
      expanded: header.open,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: logHeaderExtent,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surfaceBase,
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: Row(
            children: [
              Icon(
                header.open
                    ? PhosphorIconsRegular.caretDown
                    : PhosphorIconsRegular.caretRight,
                size: context.xpSizes.iconXs,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              XpStatusIcon(
                step == null ? XpStatus.jobQueued : stepStatus(step.state),
              ),
              const SizedBox(width: 6),
              Text(
                step == null
                    ? l10n.jobStep(header.ordinal + 1)
                    : l10n.stepKind(step.kind),
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              if (ran != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatDuration(ran),
                  style: type.code.copyWith(color: colors.textSecondary),
                ),
              ],
              const Spacer(),
              if (!header.open && header.count > 0)
                Text(
                  l10n.logLines(header.count),
                  style: type.code.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const new(
    this.item, {
    required this.wrap,
    required this.timestamps,
    required this.onCopy,
  });

  final _Line item;
  final bool wrap;
  final bool timestamps;

  /// Copies the line with where it is.
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final mono = context.xpType.mono;
    final line = item.line;
    final dim = mono.copyWith(color: colors.logDim);
    return Container(
      color: item.error
          ? colors.logErrorRow
          : item.current
          ? colors.logCurrentRow
          : line.stream == LogStream.stderr
          ? colors.logStderrRow
          : null,
      constraints: const BoxConstraints(minHeight: logLineExtent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: context.l10n.logCopyLine(line.seq),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onCopy,
                child: Container(
                  width: 52,
                  color: colors.logGutter,
                  padding: const EdgeInsets.only(right: 8),
                  alignment: Alignment.topRight,
                  child: Text('${line.seq}', style: dim),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (timestamps) ...[
            Text(formatClock(line.at), style: dim),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text.rich(
              ansiSpan(
                parseAnsi(line.text),
                mono.copyWith(color: colors.logText),
                colors,
              ),
              softWrap: wrap,
              overflow: wrap ? null : TextOverflow.clip,
              maxLines: wrap ? null : 1,
            ),
          ),
        ],
      ),
    );
  }
}
