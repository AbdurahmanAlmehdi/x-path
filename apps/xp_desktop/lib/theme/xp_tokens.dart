// XPath tokens — GENERATED from xp-tokens.json. Do not edit by hand.
// Each field maps one to one to a token path and a CSS custom property:
//   color.surface.raised  →  XpColors.surfaceRaised  →  --xp-color-surface-raised
// Generated: lints are off, as for any generated file. Copied from
// docs/design/system/project/assets/Handoff; only the import changed
// (material_ui instead of flutter/material) and the icons come from
// phosphor_icons.dart (see there why).
// ignore_for_file: type=lint
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/phosphor_icons.dart';

/// Semantic colours. Never use raw hues in widgets.
@immutable
class XpColors extends ThemeExtension<XpColors> {
  const XpColors({
    required this.surfaceWindow,
    required this.surfaceSidebar,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.surfaceOverlay,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.surfaceInverse,
    required this.surfaceSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnAccent,
    required this.textOnInverse,
    required this.textDisabled,
    required this.textLink,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.accentDefault,
    required this.accentHover,
    required this.accentPressed,
    required this.accentContainer,
    required this.accentOnContainer,
    required this.accentOnAccent,
    required this.positiveDefault,
    required this.positiveOnPositive,
    required this.negativeDefault,
    required this.negativeHover,
    required this.negativePressed,
    required this.negativeOnNegative,
    required this.warningDefault,
    required this.warningHover,
    required this.warningPressed,
    required this.warningOnWarning,
    required this.infoDefault,
    required this.infoOnInfo,
    required this.focusRing,
    required this.selectionDefault,
    required this.scrimDefault,
    required this.agentInk,
    required this.agentContainer,
    required this.statusNeutralContainer,
    required this.statusNeutralOnContainer,
    required this.statusInfoContainer,
    required this.statusInfoOnContainer,
    required this.statusAttentionContainer,
    required this.statusAttentionOnContainer,
    required this.statusPositiveContainer,
    required this.statusPositiveOnContainer,
    required this.statusNegativeContainer,
    required this.statusNegativeOnContainer,
    required this.statusCautionContainer,
    required this.statusCautionOnContainer,
    required this.statusMergedContainer,
    required this.statusMergedOnContainer,
    required this.logSurface,
    required this.logGutter,
    required this.logText,
    required this.logDim,
    required this.logStderrRow,
    required this.logErrorRow,
    required this.logMatch,
    required this.logMatchActive,
    required this.logMatchActiveText,
    required this.logCurrentRow,
    required this.codeSurface,
    required this.codeText,
    required this.codeGutter,
    required this.logAnsiBlack,
    required this.logAnsiRed,
    required this.logAnsiGreen,
    required this.logAnsiYellow,
    required this.logAnsiBlue,
    required this.logAnsiMagenta,
    required this.logAnsiCyan,
    required this.logAnsiWhite,
    required this.logAnsiBrightBlack,
    required this.logAnsiBrightRed,
    required this.logAnsiBrightGreen,
    required this.logAnsiBrightYellow,
    required this.logAnsiBrightBlue,
    required this.logAnsiBrightMagenta,
    required this.logAnsiBrightCyan,
    required this.logAnsiBrightWhite,
    required this.codeKey,
    required this.codeString,
    required this.codeNumber,
    required this.codeKeyword,
    required this.codeComment,
    required this.codeError,
  });

  /// `color.surface.window` · --xp-color-surface-window. Content area behind panels: the paper the run sheet sits on.
  final Color surfaceWindow;

  /// `color.surface.sidebar` · --xp-color-surface-sidebar. Sidebar and the collapsed console strip. Flutter may make it translucent on macOS; this is the opaque fallback and the web value.
  final Color surfaceSidebar;

  /// `color.surface.base` · --xp-color-surface-base. Toolbar / window title area and pane headers.
  final Color surfaceBase;

  /// `color.surface.raised` · --xp-color-surface-raised. Panels on the window: pipeline rail, ledger, cards, table bodies. Dark: one tint step up, no shadow.
  final Color surfaceRaised;

  /// `color.surface.sunken` · --xp-color-surface-sunken. Wells inside a raised panel: text fields, code blocks, meter tracks, skeleton base.
  final Color surfaceSunken;

  /// `color.surface.overlay` · --xp-color-surface-overlay. Menus, popovers, command palette, sheets, dialogs, toasts. Dark: two tint steps up, no shadow.
  final Color surfaceOverlay;

  /// `color.surface.hover` · --xp-color-surface-hover. Hover fill for rows, sidebar items and tertiary buttons on base, raised or sidebar.
  final Color surfaceHover;

  /// `color.surface.pressed` · --xp-color-surface-pressed. Pressed fill for the same.
  final Color surfacePressed;

  /// `color.surface.inverse` · --xp-color-surface-inverse. Inverse fill: selected segment, tooltips, the copied-SHA confirmation.
  final Color surfaceInverse;

  /// `color.surface.selected` · --xp-color-surface-selected. Selected sidebar item: sheet plus an inset strong border (see Sidebar).
  final Color surfaceSelected;

  /// `color.text.primary` · --xp-color-text-primary. Body copy, names, values. Reads on every surface and every status container.
  final Color textPrimary;

  /// `color.text.secondary` · --xp-color-text-secondary. Metadata, column heads, runner names, timestamps in chrome. Reads on every surface.
  final Color textSecondary;

  /// `color.text.tertiary` · --xp-color-text-tertiary. Placeholders, separators set as text, shortcut hints, line numbers in chrome. Reads 4.5:1 on every surface.
  final Color textTertiary;

  /// `color.text.on-accent` · --xp-color-text-on-accent. Label on an accent fill (primary button, selected segmented item in accent).
  final Color textOnAccent;

  /// `color.text.on-inverse` · --xp-color-text-on-inverse. Text and icons on surface.inverse.
  final Color textOnInverse;

  /// `color.text.disabled` · --xp-color-text-disabled. Disabled control labels only. Exempt from 4.5:1 (WCAG 1.4.3 incidental); never used for information.
  final Color textDisabled;

  /// `color.text.link` · --xp-color-text-link. Inline links and 'All jobs' style text buttons.
  final Color textLink;

  /// `color.border.subtle` · --xp-color-border-subtle. Row dividers inside a table or list.
  final Color borderSubtle;

  /// `color.border.default` · --xp-color-border-default. Panel hairlines, pane separators, button outlines (labels identify buttons).
  final Color borderDefault;

  /// `color.border.strong` · --xp-color-border-strong. Boundaries that alone identify a control: text fields, checkboxes, toggles off, selected sidebar item. 3:1 on raised, window and sunken.
  final Color borderStrong;

  /// `color.accent.default` · --xp-color-accent-default. The one primary action per screen (Dispatch…, Approve), focused segmented item, links. Never a status.
  final Color accentDefault;

  /// `color.accent.hover` · --xp-color-accent-hover. Primary button hover.
  final Color accentHover;

  /// `color.accent.pressed` · --xp-color-accent-pressed. Primary button pressed.
  final Color accentPressed;

  /// `color.accent.container` · --xp-color-accent-container. Selected text range and selected table rows; accent-tinted wells.
  final Color accentContainer;

  /// `color.accent.on-container` · --xp-color-accent-on-container. Text on accent.container.
  final Color accentOnContainer;

  /// `color.accent.on-accent` · --xp-color-accent-on-accent. Alias of text.on-accent, kept so accent has its own pair.
  final Color accentOnAccent;

  /// `color.positive.default` · --xp-color-positive-default. Success strokes and fills (meters, rollout bars, diff '+'). As text: raised, window, base.
  final Color positiveDefault;

  /// `color.positive.on-positive` · --xp-color-positive-on-positive. Text on a positive fill.
  final Color positiveOnPositive;

  /// `color.negative.default` · --xp-color-negative-default. Destructive button fill, failure strokes, error underline in the YAML editor.
  final Color negativeDefault;

  /// `color.negative.hover` · --xp-color-negative-hover. Destructive button hover.
  final Color negativeHover;

  /// `color.negative.pressed` · --xp-color-negative-pressed. Destructive button pressed.
  final Color negativePressed;

  /// `color.negative.on-negative` · --xp-color-negative-on-negative. Text on a negative fill.
  final Color negativeOnNegative;

  /// `color.warning.default` · --xp-color-warning-default. The single loud fill: needs-you count badge and Review… button. Same in both themes.
  final Color warningDefault;

  /// `color.warning.hover` · --xp-color-warning-hover. Review… button hover.
  final Color warningHover;

  /// `color.warning.pressed` · --xp-color-warning-pressed. Review… button pressed.
  final Color warningPressed;

  /// `color.warning.on-warning` · --xp-color-warning-on-warning. Text on the warning fill.
  final Color warningOnWarning;

  /// `color.info.default` · --xp-color-info-default. Running strokes: running node border, progress bars, follow-tail caret.
  final Color infoDefault;

  /// `color.info.on-info` · --xp-color-info-on-info. Text on an info fill.
  final Color infoOnInfo;

  /// `color.focus.ring` · --xp-color-focus-ring. Keyboard focus: 2px solid ring, 2px offset in the surface colour. 3:1 on every surface in both themes.
  final Color focusRing;

  /// `color.selection.default` · --xp-color-selection-default. Text selection highlight and multi-select rows. Primary text stays legible on it.
  final Color selectionDefault;

  /// `color.scrim.default` · --xp-color-scrim-default. Behind sheets and dialogs.
  final Color scrimDefault;

  /// `color.agent.ink` · --xp-color-agent-ink. Agent marker border (1px dashed), robot icon and label. Deliberately colourless: it says who, not how things are going.
  final Color agentInk;

  /// `color.agent.container` · --xp-color-agent-container. Agent marker fill when it sits on a status container or in a dense table; transparent elsewhere.
  final Color agentContainer;

  /// `color.status.neutral.container` · --xp-color-status-neutral-container. Status container (neutral). Nothing to do and nothing wrong: queued, waiting, skipped, cancelled, draft, offline, unknown.
  final Color statusNeutralContainer;

  /// `color.status.neutral.on-container` · --xp-color-status-neutral-on-container. Status icon + label on status.neutral.container, and inline on raised, window, base and overlay.
  final Color statusNeutralOnContainer;

  /// `color.status.info.container` · --xp-color-status-info-container. Status container (info). Something is moving: running, building, in review, processing, busy, updating, scan info.
  final Color statusInfoContainer;

  /// `color.status.info.on-container` · --xp-color-status-info-on-container. Status icon + label on status.info.container, and inline on raised, window, base and overlay.
  final Color statusInfoOnContainer;

  /// `color.status.attention.container` · --xp-color-status-attention-container. Status container (attention). A human must act: waiting for approval, ready to submit, pending developer release, secrets locked.
  final Color statusAttentionContainer;

  /// `color.status.attention.on-container` · --xp-color-status-attention-on-container. Status icon + label on status.attention.container, and inline on raised, window, base and overlay.
  final Color statusAttentionOnContainer;

  /// `color.status.positive.container` · --xp-color-status-positive-container. Status container (positive). Done and good: succeeded, approved, live, published, verified, connected, idle runner.
  final Color statusPositiveContainer;

  /// `color.status.positive.on-container` · --xp-color-status-positive-on-container. Status icon + label on status.positive.container, and inline on raised, window, base and overlay.
  final Color statusPositiveOnContainer;

  /// `color.status.negative.container` · --xp-color-status-negative-container. Status container (negative). Broken or refused: failed, rejected, denied, not approved, expired credential, unreachable, scan error.
  final Color statusNegativeContainer;

  /// `color.status.negative.on-container` · --xp-color-status-negative-on-container. Status icon + label on status.negative.container, and inline on raised, window, base and overlay.
  final Color statusNegativeOnContainer;

  /// `color.status.caution.container` · --xp-color-status-caution-container. Status container (caution). Degraded but not blocked: interrupted, reconnecting, expiring soon, missing credential, scan warning.
  final Color statusCautionContainer;

  /// `color.status.caution.on-container` · --xp-color-status-caution-on-container. Status icon + label on status.caution.container, and inline on raised, window, base and overlay.
  final Color statusCautionOnContainer;

  /// `color.status.merged.container` · --xp-color-status-merged-container. Status container (merged). Terminal success of a release: merged into main.
  final Color statusMergedContainer;

  /// `color.status.merged.on-container` · --xp-color-status-merged-on-container. Status icon + label on status.merged.container, and inline on raised, window, base and overlay.
  final Color statusMergedOnContainer;

  /// `color.log.surface` · --xp-color-log-surface. Console / log viewer background. Only surface where ANSI colour may appear.
  final Color logSurface;

  /// `color.log.gutter` · --xp-color-log-gutter. Line-number gutter and sticky step header.
  final Color logGutter;

  /// `color.log.text` · --xp-color-log-text. Default log text (ANSI default foreground).
  final Color logText;

  /// `color.log.dim` · --xp-color-log-dim. Line numbers, timestamps, ANSI dim on default text.
  final Color logDim;

  /// `color.log.stderr-row` · --xp-color-log-stderr-row. Row tint for stderr lines when 'stderr only' is off.
  final Color logStderrRow;

  /// `color.log.error-row` · --xp-color-log-error-row. Row tint for the line 'Jump to error' lands on and lines matched as errors.
  final Color logErrorRow;

  /// `color.log.match` · --xp-color-log-match. Search match highlight.
  final Color logMatch;

  /// `color.log.match-active` · --xp-color-log-match-active. Current search match (text stays log.text in light, #141412 in dark via log.match-active-text).
  final Color logMatchActive;

  /// `color.log.match-active-text` · --xp-color-log-match-active-text. Text on the current search match.
  final Color logMatchActiveText;

  /// `color.log.current-row` · --xp-color-log-current-row. The streaming tail line while following.
  final Color logCurrentRow;

  /// `color.code.surface` · --xp-color-code-surface. YAML editor background (same as the log).
  final Color codeSurface;

  /// `color.code.text` · --xp-color-code-text. Plain YAML text.
  final Color codeText;

  /// `color.code.gutter` · --xp-color-code-gutter. Line-number gutter in the YAML editor.
  final Color codeGutter;

  /// `color.log.ansi.black` · --xp-color-log-ansi-black. ANSI black (SGR 30) on log.surface. Remapped in dark so it stays legible.
  final Color logAnsiBlack;

  /// `color.log.ansi.red` · --xp-color-log-ansi-red. ANSI red (SGR 31) on log.surface.
  final Color logAnsiRed;

  /// `color.log.ansi.green` · --xp-color-log-ansi-green. ANSI green (SGR 32) on log.surface.
  final Color logAnsiGreen;

  /// `color.log.ansi.yellow` · --xp-color-log-ansi-yellow. ANSI yellow (SGR 33) on log.surface.
  final Color logAnsiYellow;

  /// `color.log.ansi.blue` · --xp-color-log-ansi-blue. ANSI blue (SGR 34) on log.surface.
  final Color logAnsiBlue;

  /// `color.log.ansi.magenta` · --xp-color-log-ansi-magenta. ANSI magenta (SGR 35) on log.surface.
  final Color logAnsiMagenta;

  /// `color.log.ansi.cyan` · --xp-color-log-ansi-cyan. ANSI cyan (SGR 36) on log.surface.
  final Color logAnsiCyan;

  /// `color.log.ansi.white` · --xp-color-log-ansi-white. ANSI white (SGR 37) on log.surface. Remapped in light so it stays legible.
  final Color logAnsiWhite;

  /// `color.log.ansi.bright-black` · --xp-color-log-ansi-bright-black. ANSI bright-black (SGR 90) on log.surface.
  final Color logAnsiBrightBlack;

  /// `color.log.ansi.bright-red` · --xp-color-log-ansi-bright-red. ANSI bright-red (SGR 91) on log.surface.
  final Color logAnsiBrightRed;

  /// `color.log.ansi.bright-green` · --xp-color-log-ansi-bright-green. ANSI bright-green (SGR 92) on log.surface.
  final Color logAnsiBrightGreen;

  /// `color.log.ansi.bright-yellow` · --xp-color-log-ansi-bright-yellow. ANSI bright-yellow (SGR 93) on log.surface.
  final Color logAnsiBrightYellow;

  /// `color.log.ansi.bright-blue` · --xp-color-log-ansi-bright-blue. ANSI bright-blue (SGR 94) on log.surface.
  final Color logAnsiBrightBlue;

  /// `color.log.ansi.bright-magenta` · --xp-color-log-ansi-bright-magenta. ANSI bright-magenta (SGR 95) on log.surface.
  final Color logAnsiBrightMagenta;

  /// `color.log.ansi.bright-cyan` · --xp-color-log-ansi-bright-cyan. ANSI bright-cyan (SGR 96) on log.surface.
  final Color logAnsiBrightCyan;

  /// `color.log.ansi.bright-white` · --xp-color-log-ansi-bright-white. ANSI bright-white (SGR 97) on log.surface. Remapped in light so it stays legible.
  final Color logAnsiBrightWhite;

  /// `color.code.key` · --xp-color-code-key. YAML keys.
  final Color codeKey;

  /// `color.code.string` · --xp-color-code-string. YAML strings.
  final Color codeString;

  /// `color.code.number` · --xp-color-code-number. Numbers and versions in YAML.
  final Color codeNumber;

  /// `color.code.keyword` · --xp-color-code-keyword. Booleans, null, anchors and aliases.
  final Color codeKeyword;

  /// `color.code.comment` · --xp-color-code-comment. Comments.
  final Color codeComment;

  /// `color.code.error` · --xp-color-code-error. Wavy error underline and gutter marker.
  final Color codeError;

  static const light = XpColors(
    surfaceWindow: Color(0xFFF6F5F1),
    surfaceSidebar: Color(0xFFEDECE6),
    surfaceBase: Color(0xFFFBFAF7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFEEE8),
    surfaceOverlay: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF1F0EB),
    surfacePressed: Color(0xFFE6E5DE),
    surfaceInverse: Color(0xFF1B1B18),
    surfaceSelected: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1B1B18),
    textSecondary: Color(0xFF5C5B54),
    textTertiary: Color(0xFF64625B),
    textOnAccent: Color(0xFFFFFFFF),
    textOnInverse: Color(0xFFFFFFFF),
    textDisabled: Color(0xFFA6A49C),
    textLink: Color(0xFF2449B8),
    borderSubtle: Color(0xFFEDEBE5),
    borderDefault: Color(0xFFE3E1DA),
    borderStrong: Color(0xFF8C897F),
    accentDefault: Color(0xFF2449B8),
    accentHover: Color(0xFF1E3E9E),
    accentPressed: Color(0xFF183284),
    accentContainer: Color(0xFFE6ECFB),
    accentOnContainer: Color(0xFF163A9E),
    accentOnAccent: Color(0xFFFFFFFF),
    positiveDefault: Color(0xFF1E7A4C),
    positiveOnPositive: Color(0xFFFFFFFF),
    negativeDefault: Color(0xFFB42318),
    negativeHover: Color(0xFF9A1D13),
    negativePressed: Color(0xFF821910),
    negativeOnNegative: Color(0xFFFFFFFF),
    warningDefault: Color(0xFFF0B44C),
    warningHover: Color(0xFFE5A63C),
    warningPressed: Color(0xFFD4972F),
    warningOnWarning: Color(0xFF1B1408),
    infoDefault: Color(0xFF2459C2),
    infoOnInfo: Color(0xFFFFFFFF),
    focusRing: Color(0xFF2449B8),
    selectionDefault: Color(0xFFCFDBF6),
    scrimDefault: Color.fromRGBO(27, 27, 24, 0.32),
    agentInk: Color(0xFF1B1B18),
    agentContainer: Color(0xFFF3F1EA),
    statusNeutralContainer: Color(0xFFECEBE5),
    statusNeutralOnContainer: Color(0xFF4A4943),
    statusInfoContainer: Color(0xFFE4EBFA),
    statusInfoOnContainer: Color(0xFF1F4FB0),
    statusAttentionContainer: Color(0xFFFFF0D1),
    statusAttentionOnContainer: Color(0xFF6E3C00),
    statusPositiveContainer: Color(0xFFE3F3EA),
    statusPositiveOnContainer: Color(0xFF17663F),
    statusNegativeContainer: Color(0xFFFDE8E6),
    statusNegativeOnContainer: Color(0xFFA11F14),
    statusCautionContainer: Color(0xFFFCEBDD),
    statusCautionOnContainer: Color(0xFF8A3606),
    statusMergedContainer: Color(0xFFEEE9FA),
    statusMergedOnContainer: Color(0xFF4B2FA0),
    logSurface: Color(0xFFFCFBF8),
    logGutter: Color(0xFFF3F2EC),
    logText: Color(0xFF22221E),
    logDim: Color(0xFF66645D),
    logStderrRow: Color(0xFFFFF6E0),
    logErrorRow: Color(0xFFFDECEA),
    logMatch: Color(0xFFFCE7A6),
    logMatchActive: Color(0xFFF0B44C),
    logMatchActiveText: Color(0xFF1B1408),
    logCurrentRow: Color(0xFFEEF2FC),
    codeSurface: Color(0xFFFCFBF8),
    codeText: Color(0xFF22221E),
    codeGutter: Color(0xFFF3F2EC),
    logAnsiBlack: Color(0xFF1B1B18),
    logAnsiRed: Color(0xFFB42318),
    logAnsiGreen: Color(0xFF1B6E44),
    logAnsiYellow: Color(0xFF8A5300),
    logAnsiBlue: Color(0xFF2449B8),
    logAnsiMagenta: Color(0xFF8E2A86),
    logAnsiCyan: Color(0xFF0B6874),
    logAnsiWhite: Color(0xFF5C5B54),
    logAnsiBrightBlack: Color(0xFF66645D),
    logAnsiBrightRed: Color(0xFFC2300F),
    logAnsiBrightGreen: Color(0xFF227A4E),
    logAnsiBrightYellow: Color(0xFF9A5B00),
    logAnsiBrightBlue: Color(0xFF2D5BD6),
    logAnsiBrightMagenta: Color(0xFFA2349A),
    logAnsiBrightCyan: Color(0xFF0D7684),
    logAnsiBrightWhite: Color(0xFF3B3A35),
    codeKey: Color(0xFF2449B8),
    codeString: Color(0xFF1B6E44),
    codeNumber: Color(0xFF8E2A86),
    codeKeyword: Color(0xFF0B6874),
    codeComment: Color(0xFF66645D),
    codeError: Color(0xFFB42318),
  );

  static const dark = XpColors(
    surfaceWindow: Color(0xFF141412),
    surfaceSidebar: Color(0xFF191917),
    surfaceBase: Color(0xFF1A1A18),
    surfaceRaised: Color(0xFF1E1E1B),
    surfaceSunken: Color(0xFF121210),
    surfaceOverlay: Color(0xFF262623),
    surfaceHover: Color(0xFF262622),
    surfacePressed: Color(0xFF2E2D29),
    surfaceInverse: Color(0xFFECEAE3),
    surfaceSelected: Color(0xFF2A2A25),
    textPrimary: Color(0xFFECEAE3),
    textSecondary: Color(0xFFA8A59B),
    textTertiary: Color(0xFF97948A),
    textOnAccent: Color(0xFF0F1424),
    textOnInverse: Color(0xFF141412),
    textDisabled: Color(0xFF5E5C55),
    textLink: Color(0xFF8FB0FF),
    borderSubtle: Color(0xFF262622),
    borderDefault: Color(0xFF33322D),
    borderStrong: Color(0xFF7A776D),
    accentDefault: Color(0xFF7EA2FF),
    accentHover: Color(0xFF97B5FF),
    accentPressed: Color(0xFF6A8DEB),
    accentContainer: Color(0xFF1D2742),
    accentOnContainer: Color(0xFFB5CAFF),
    accentOnAccent: Color(0xFF0F1424),
    positiveDefault: Color(0xFF4CC38A),
    positiveOnPositive: Color(0xFF0B1F14),
    negativeDefault: Color(0xFFF97066),
    negativeHover: Color(0xFFFF8A80),
    negativePressed: Color(0xFFE85D53),
    negativeOnNegative: Color(0xFF1F0806),
    warningDefault: Color(0xFFF0B44C),
    warningHover: Color(0xFFF5C26A),
    warningPressed: Color(0xFFE0A443),
    warningOnWarning: Color(0xFF1B1408),
    infoDefault: Color(0xFF6FA8FF),
    infoOnInfo: Color(0xFF0D1729),
    focusRing: Color(0xFF8FB0FF),
    selectionDefault: Color(0xFF2B3B63),
    scrimDefault: Color.fromRGBO(0, 0, 0, 0.56),
    agentInk: Color(0xFFECEAE3),
    agentContainer: Color(0xFF22221F),
    statusNeutralContainer: Color(0xFF2A2925),
    statusNeutralOnContainer: Color(0xFFCFCBBF),
    statusInfoContainer: Color(0xFF172238),
    statusInfoOnContainer: Color(0xFF8FBBFF),
    statusAttentionContainer: Color(0xFF2D2310),
    statusAttentionOnContainer: Color(0xFFF5C873),
    statusPositiveContainer: Color(0xFF12291D),
    statusPositiveOnContainer: Color(0xFF5CCB94),
    statusNegativeContainer: Color(0xFF3A1614),
    statusNegativeOnContainer: Color(0xFFFF8A80),
    statusCautionContainer: Color(0xFF33200F),
    statusCautionOnContainer: Color(0xFFF6A35C),
    statusMergedContainer: Color(0xFF241C3A),
    statusMergedOnContainer: Color(0xFFBBA6FF),
    logSurface: Color(0xFF10100E),
    logGutter: Color(0xFF151513),
    logText: Color(0xFFDAD7CE),
    logDim: Color(0xFF8F8C83),
    logStderrRow: Color(0xFF241D10),
    logErrorRow: Color(0xFF2C1513),
    logMatch: Color(0xFF5A4713),
    logMatchActive: Color(0xFFF0B44C),
    logMatchActiveText: Color(0xFF1B1408),
    logCurrentRow: Color(0xFF1A2232),
    codeSurface: Color(0xFF10100E),
    codeText: Color(0xFFDAD7CE),
    codeGutter: Color(0xFF151513),
    logAnsiBlack: Color(0xFF8F8C83),
    logAnsiRed: Color(0xFFF97066),
    logAnsiGreen: Color(0xFF4CC38A),
    logAnsiYellow: Color(0xFFF5C873),
    logAnsiBlue: Color(0xFF7EA2FF),
    logAnsiMagenta: Color(0xFFE08BE0),
    logAnsiCyan: Color(0xFF5CC8D6),
    logAnsiWhite: Color(0xFFDAD7CE),
    logAnsiBrightBlack: Color(0xFFA8A59B),
    logAnsiBrightRed: Color(0xFFFF968E),
    logAnsiBrightGreen: Color(0xFF78DAA9),
    logAnsiBrightYellow: Color(0xFFFFDC8F),
    logAnsiBrightBlue: Color(0xFFA6C0FF),
    logAnsiBrightMagenta: Color(0xFFF2B2F2),
    logAnsiBrightCyan: Color(0xFF8FE1EB),
    logAnsiBrightWhite: Color(0xFFFFFFFF),
    codeKey: Color(0xFF7EA2FF),
    codeString: Color(0xFF4CC38A),
    codeNumber: Color(0xFFE08BE0),
    codeKeyword: Color(0xFF5CC8D6),
    codeComment: Color(0xFF8F8C83),
    codeError: Color(0xFFF97066),
  );

  @override
  XpColors copyWith({
    Color? surfaceWindow,
    Color? surfaceSidebar,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? surfaceOverlay,
    Color? surfaceHover,
    Color? surfacePressed,
    Color? surfaceInverse,
    Color? surfaceSelected,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnAccent,
    Color? textOnInverse,
    Color? textDisabled,
    Color? textLink,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? accentDefault,
    Color? accentHover,
    Color? accentPressed,
    Color? accentContainer,
    Color? accentOnContainer,
    Color? accentOnAccent,
    Color? positiveDefault,
    Color? positiveOnPositive,
    Color? negativeDefault,
    Color? negativeHover,
    Color? negativePressed,
    Color? negativeOnNegative,
    Color? warningDefault,
    Color? warningHover,
    Color? warningPressed,
    Color? warningOnWarning,
    Color? infoDefault,
    Color? infoOnInfo,
    Color? focusRing,
    Color? selectionDefault,
    Color? scrimDefault,
    Color? agentInk,
    Color? agentContainer,
    Color? statusNeutralContainer,
    Color? statusNeutralOnContainer,
    Color? statusInfoContainer,
    Color? statusInfoOnContainer,
    Color? statusAttentionContainer,
    Color? statusAttentionOnContainer,
    Color? statusPositiveContainer,
    Color? statusPositiveOnContainer,
    Color? statusNegativeContainer,
    Color? statusNegativeOnContainer,
    Color? statusCautionContainer,
    Color? statusCautionOnContainer,
    Color? statusMergedContainer,
    Color? statusMergedOnContainer,
    Color? logSurface,
    Color? logGutter,
    Color? logText,
    Color? logDim,
    Color? logStderrRow,
    Color? logErrorRow,
    Color? logMatch,
    Color? logMatchActive,
    Color? logMatchActiveText,
    Color? logCurrentRow,
    Color? codeSurface,
    Color? codeText,
    Color? codeGutter,
    Color? logAnsiBlack,
    Color? logAnsiRed,
    Color? logAnsiGreen,
    Color? logAnsiYellow,
    Color? logAnsiBlue,
    Color? logAnsiMagenta,
    Color? logAnsiCyan,
    Color? logAnsiWhite,
    Color? logAnsiBrightBlack,
    Color? logAnsiBrightRed,
    Color? logAnsiBrightGreen,
    Color? logAnsiBrightYellow,
    Color? logAnsiBrightBlue,
    Color? logAnsiBrightMagenta,
    Color? logAnsiBrightCyan,
    Color? logAnsiBrightWhite,
    Color? codeKey,
    Color? codeString,
    Color? codeNumber,
    Color? codeKeyword,
    Color? codeComment,
    Color? codeError,
  }) => XpColors(
    surfaceWindow: surfaceWindow ?? this.surfaceWindow,
    surfaceSidebar: surfaceSidebar ?? this.surfaceSidebar,
    surfaceBase: surfaceBase ?? this.surfaceBase,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    surfaceHover: surfaceHover ?? this.surfaceHover,
    surfacePressed: surfacePressed ?? this.surfacePressed,
    surfaceInverse: surfaceInverse ?? this.surfaceInverse,
    surfaceSelected: surfaceSelected ?? this.surfaceSelected,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    textOnAccent: textOnAccent ?? this.textOnAccent,
    textOnInverse: textOnInverse ?? this.textOnInverse,
    textDisabled: textDisabled ?? this.textDisabled,
    textLink: textLink ?? this.textLink,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderDefault: borderDefault ?? this.borderDefault,
    borderStrong: borderStrong ?? this.borderStrong,
    accentDefault: accentDefault ?? this.accentDefault,
    accentHover: accentHover ?? this.accentHover,
    accentPressed: accentPressed ?? this.accentPressed,
    accentContainer: accentContainer ?? this.accentContainer,
    accentOnContainer: accentOnContainer ?? this.accentOnContainer,
    accentOnAccent: accentOnAccent ?? this.accentOnAccent,
    positiveDefault: positiveDefault ?? this.positiveDefault,
    positiveOnPositive: positiveOnPositive ?? this.positiveOnPositive,
    negativeDefault: negativeDefault ?? this.negativeDefault,
    negativeHover: negativeHover ?? this.negativeHover,
    negativePressed: negativePressed ?? this.negativePressed,
    negativeOnNegative: negativeOnNegative ?? this.negativeOnNegative,
    warningDefault: warningDefault ?? this.warningDefault,
    warningHover: warningHover ?? this.warningHover,
    warningPressed: warningPressed ?? this.warningPressed,
    warningOnWarning: warningOnWarning ?? this.warningOnWarning,
    infoDefault: infoDefault ?? this.infoDefault,
    infoOnInfo: infoOnInfo ?? this.infoOnInfo,
    focusRing: focusRing ?? this.focusRing,
    selectionDefault: selectionDefault ?? this.selectionDefault,
    scrimDefault: scrimDefault ?? this.scrimDefault,
    agentInk: agentInk ?? this.agentInk,
    agentContainer: agentContainer ?? this.agentContainer,
    statusNeutralContainer:
        statusNeutralContainer ?? this.statusNeutralContainer,
    statusNeutralOnContainer:
        statusNeutralOnContainer ?? this.statusNeutralOnContainer,
    statusInfoContainer: statusInfoContainer ?? this.statusInfoContainer,
    statusInfoOnContainer: statusInfoOnContainer ?? this.statusInfoOnContainer,
    statusAttentionContainer:
        statusAttentionContainer ?? this.statusAttentionContainer,
    statusAttentionOnContainer:
        statusAttentionOnContainer ?? this.statusAttentionOnContainer,
    statusPositiveContainer:
        statusPositiveContainer ?? this.statusPositiveContainer,
    statusPositiveOnContainer:
        statusPositiveOnContainer ?? this.statusPositiveOnContainer,
    statusNegativeContainer:
        statusNegativeContainer ?? this.statusNegativeContainer,
    statusNegativeOnContainer:
        statusNegativeOnContainer ?? this.statusNegativeOnContainer,
    statusCautionContainer:
        statusCautionContainer ?? this.statusCautionContainer,
    statusCautionOnContainer:
        statusCautionOnContainer ?? this.statusCautionOnContainer,
    statusMergedContainer: statusMergedContainer ?? this.statusMergedContainer,
    statusMergedOnContainer:
        statusMergedOnContainer ?? this.statusMergedOnContainer,
    logSurface: logSurface ?? this.logSurface,
    logGutter: logGutter ?? this.logGutter,
    logText: logText ?? this.logText,
    logDim: logDim ?? this.logDim,
    logStderrRow: logStderrRow ?? this.logStderrRow,
    logErrorRow: logErrorRow ?? this.logErrorRow,
    logMatch: logMatch ?? this.logMatch,
    logMatchActive: logMatchActive ?? this.logMatchActive,
    logMatchActiveText: logMatchActiveText ?? this.logMatchActiveText,
    logCurrentRow: logCurrentRow ?? this.logCurrentRow,
    codeSurface: codeSurface ?? this.codeSurface,
    codeText: codeText ?? this.codeText,
    codeGutter: codeGutter ?? this.codeGutter,
    logAnsiBlack: logAnsiBlack ?? this.logAnsiBlack,
    logAnsiRed: logAnsiRed ?? this.logAnsiRed,
    logAnsiGreen: logAnsiGreen ?? this.logAnsiGreen,
    logAnsiYellow: logAnsiYellow ?? this.logAnsiYellow,
    logAnsiBlue: logAnsiBlue ?? this.logAnsiBlue,
    logAnsiMagenta: logAnsiMagenta ?? this.logAnsiMagenta,
    logAnsiCyan: logAnsiCyan ?? this.logAnsiCyan,
    logAnsiWhite: logAnsiWhite ?? this.logAnsiWhite,
    logAnsiBrightBlack: logAnsiBrightBlack ?? this.logAnsiBrightBlack,
    logAnsiBrightRed: logAnsiBrightRed ?? this.logAnsiBrightRed,
    logAnsiBrightGreen: logAnsiBrightGreen ?? this.logAnsiBrightGreen,
    logAnsiBrightYellow: logAnsiBrightYellow ?? this.logAnsiBrightYellow,
    logAnsiBrightBlue: logAnsiBrightBlue ?? this.logAnsiBrightBlue,
    logAnsiBrightMagenta: logAnsiBrightMagenta ?? this.logAnsiBrightMagenta,
    logAnsiBrightCyan: logAnsiBrightCyan ?? this.logAnsiBrightCyan,
    logAnsiBrightWhite: logAnsiBrightWhite ?? this.logAnsiBrightWhite,
    codeKey: codeKey ?? this.codeKey,
    codeString: codeString ?? this.codeString,
    codeNumber: codeNumber ?? this.codeNumber,
    codeKeyword: codeKeyword ?? this.codeKeyword,
    codeComment: codeComment ?? this.codeComment,
    codeError: codeError ?? this.codeError,
  );

  @override
  XpColors lerp(XpColors? other, double t) {
    if (other is! XpColors) return this;
    return XpColors(
      surfaceWindow: Color.lerp(surfaceWindow, other.surfaceWindow, t)!,
      surfaceSidebar: Color.lerp(surfaceSidebar, other.surfaceSidebar, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      surfaceInverse: Color.lerp(surfaceInverse, other.surfaceInverse, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      textOnInverse: Color.lerp(textOnInverse, other.textOnInverse, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accentDefault: Color.lerp(accentDefault, other.accentDefault, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      accentOnContainer: Color.lerp(
        accentOnContainer,
        other.accentOnContainer,
        t,
      )!,
      accentOnAccent: Color.lerp(accentOnAccent, other.accentOnAccent, t)!,
      positiveDefault: Color.lerp(positiveDefault, other.positiveDefault, t)!,
      positiveOnPositive: Color.lerp(
        positiveOnPositive,
        other.positiveOnPositive,
        t,
      )!,
      negativeDefault: Color.lerp(negativeDefault, other.negativeDefault, t)!,
      negativeHover: Color.lerp(negativeHover, other.negativeHover, t)!,
      negativePressed: Color.lerp(negativePressed, other.negativePressed, t)!,
      negativeOnNegative: Color.lerp(
        negativeOnNegative,
        other.negativeOnNegative,
        t,
      )!,
      warningDefault: Color.lerp(warningDefault, other.warningDefault, t)!,
      warningHover: Color.lerp(warningHover, other.warningHover, t)!,
      warningPressed: Color.lerp(warningPressed, other.warningPressed, t)!,
      warningOnWarning: Color.lerp(
        warningOnWarning,
        other.warningOnWarning,
        t,
      )!,
      infoDefault: Color.lerp(infoDefault, other.infoDefault, t)!,
      infoOnInfo: Color.lerp(infoOnInfo, other.infoOnInfo, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      selectionDefault: Color.lerp(
        selectionDefault,
        other.selectionDefault,
        t,
      )!,
      scrimDefault: Color.lerp(scrimDefault, other.scrimDefault, t)!,
      agentInk: Color.lerp(agentInk, other.agentInk, t)!,
      agentContainer: Color.lerp(agentContainer, other.agentContainer, t)!,
      statusNeutralContainer: Color.lerp(
        statusNeutralContainer,
        other.statusNeutralContainer,
        t,
      )!,
      statusNeutralOnContainer: Color.lerp(
        statusNeutralOnContainer,
        other.statusNeutralOnContainer,
        t,
      )!,
      statusInfoContainer: Color.lerp(
        statusInfoContainer,
        other.statusInfoContainer,
        t,
      )!,
      statusInfoOnContainer: Color.lerp(
        statusInfoOnContainer,
        other.statusInfoOnContainer,
        t,
      )!,
      statusAttentionContainer: Color.lerp(
        statusAttentionContainer,
        other.statusAttentionContainer,
        t,
      )!,
      statusAttentionOnContainer: Color.lerp(
        statusAttentionOnContainer,
        other.statusAttentionOnContainer,
        t,
      )!,
      statusPositiveContainer: Color.lerp(
        statusPositiveContainer,
        other.statusPositiveContainer,
        t,
      )!,
      statusPositiveOnContainer: Color.lerp(
        statusPositiveOnContainer,
        other.statusPositiveOnContainer,
        t,
      )!,
      statusNegativeContainer: Color.lerp(
        statusNegativeContainer,
        other.statusNegativeContainer,
        t,
      )!,
      statusNegativeOnContainer: Color.lerp(
        statusNegativeOnContainer,
        other.statusNegativeOnContainer,
        t,
      )!,
      statusCautionContainer: Color.lerp(
        statusCautionContainer,
        other.statusCautionContainer,
        t,
      )!,
      statusCautionOnContainer: Color.lerp(
        statusCautionOnContainer,
        other.statusCautionOnContainer,
        t,
      )!,
      statusMergedContainer: Color.lerp(
        statusMergedContainer,
        other.statusMergedContainer,
        t,
      )!,
      statusMergedOnContainer: Color.lerp(
        statusMergedOnContainer,
        other.statusMergedOnContainer,
        t,
      )!,
      logSurface: Color.lerp(logSurface, other.logSurface, t)!,
      logGutter: Color.lerp(logGutter, other.logGutter, t)!,
      logText: Color.lerp(logText, other.logText, t)!,
      logDim: Color.lerp(logDim, other.logDim, t)!,
      logStderrRow: Color.lerp(logStderrRow, other.logStderrRow, t)!,
      logErrorRow: Color.lerp(logErrorRow, other.logErrorRow, t)!,
      logMatch: Color.lerp(logMatch, other.logMatch, t)!,
      logMatchActive: Color.lerp(logMatchActive, other.logMatchActive, t)!,
      logMatchActiveText: Color.lerp(
        logMatchActiveText,
        other.logMatchActiveText,
        t,
      )!,
      logCurrentRow: Color.lerp(logCurrentRow, other.logCurrentRow, t)!,
      codeSurface: Color.lerp(codeSurface, other.codeSurface, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      codeGutter: Color.lerp(codeGutter, other.codeGutter, t)!,
      logAnsiBlack: Color.lerp(logAnsiBlack, other.logAnsiBlack, t)!,
      logAnsiRed: Color.lerp(logAnsiRed, other.logAnsiRed, t)!,
      logAnsiGreen: Color.lerp(logAnsiGreen, other.logAnsiGreen, t)!,
      logAnsiYellow: Color.lerp(logAnsiYellow, other.logAnsiYellow, t)!,
      logAnsiBlue: Color.lerp(logAnsiBlue, other.logAnsiBlue, t)!,
      logAnsiMagenta: Color.lerp(logAnsiMagenta, other.logAnsiMagenta, t)!,
      logAnsiCyan: Color.lerp(logAnsiCyan, other.logAnsiCyan, t)!,
      logAnsiWhite: Color.lerp(logAnsiWhite, other.logAnsiWhite, t)!,
      logAnsiBrightBlack: Color.lerp(
        logAnsiBrightBlack,
        other.logAnsiBrightBlack,
        t,
      )!,
      logAnsiBrightRed: Color.lerp(
        logAnsiBrightRed,
        other.logAnsiBrightRed,
        t,
      )!,
      logAnsiBrightGreen: Color.lerp(
        logAnsiBrightGreen,
        other.logAnsiBrightGreen,
        t,
      )!,
      logAnsiBrightYellow: Color.lerp(
        logAnsiBrightYellow,
        other.logAnsiBrightYellow,
        t,
      )!,
      logAnsiBrightBlue: Color.lerp(
        logAnsiBrightBlue,
        other.logAnsiBrightBlue,
        t,
      )!,
      logAnsiBrightMagenta: Color.lerp(
        logAnsiBrightMagenta,
        other.logAnsiBrightMagenta,
        t,
      )!,
      logAnsiBrightCyan: Color.lerp(
        logAnsiBrightCyan,
        other.logAnsiBrightCyan,
        t,
      )!,
      logAnsiBrightWhite: Color.lerp(
        logAnsiBrightWhite,
        other.logAnsiBrightWhite,
        t,
      )!,
      codeKey: Color.lerp(codeKey, other.codeKey, t)!,
      codeString: Color.lerp(codeString, other.codeString, t)!,
      codeNumber: Color.lerp(codeNumber, other.codeNumber, t)!,
      codeKeyword: Color.lerp(codeKeyword, other.codeKeyword, t)!,
      codeComment: Color.lerp(codeComment, other.codeComment, t)!,
      codeError: Color.lerp(codeError, other.codeError, t)!,
    );
  }
}

/// Type roles. Colour comes from XpColors at the call site; type.label is upper-cased by the widget.
@immutable
class XpTypography extends ThemeExtension<XpTypography> {
  const XpTypography({
    required this.hero,
    required this.heroCode,
    required this.display,
    required this.headline,
    required this.title,
    required this.titleSm,
    required this.body,
    required this.bodyStrong,
    required this.caption,
    required this.label,
    required this.code,
    required this.codeLg,
    required this.mono,
  });

  /// `type.hero` · --xp-type-hero. The one big thing a screen is for: a release's state, a job's result, a pending approval's action. One per screen. Versions inside it switch to type.hero-code.
  final TextStyle hero;

  /// `type.hero-code` · --xp-type-hero-code. Version or build inside a hero line. Tabular figures.
  final TextStyle heroCode;

  /// `type.display` · --xp-type-display. Onboarding and empty-state headlines only.
  final TextStyle display;

  /// `type.headline` · --xp-type-headline. Screen titles inside the content area (app header, sheet title).
  final TextStyle headline;

  /// `type.title` · --xp-type-title. Panel titles, toolbar title, card titles.
  final TextStyle title;

  /// `type.title-sm` · --xp-type-title-sm. Row titles, sidebar selected project, flavor names.
  final TextStyle titleSm;

  /// `type.body` · --xp-type-body. Default UI text.
  final TextStyle body;

  /// `type.body-strong` · --xp-type-body-strong. Emphasis inside body and button labels.
  final TextStyle bodyStrong;

  /// `type.caption` · --xp-type-caption. Metadata under a row title, helper text, timestamps in prose.
  final TextStyle caption;

  /// `type.label` · --xp-type-label. Section and column labels, set in mono caps. Never for sentences.
  final TextStyle label;

  /// `type.code` · --xp-type-code. Versions, build numbers, SHAs, bundle IDs, tags, durations, sizes. Tabular figures, copyable.
  final TextStyle code;

  /// `type.code-lg` · --xp-type-code-lg. Versions in the ledger's cells and card headers.
  final TextStyle codeLg;

  /// `type.mono` · --xp-type-mono. Log lines. ANSI bold = weight 600; dim = log.dim colour.
  final TextStyle mono;

  static const standard = XpTypography(
    hero: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 28,
      height: 1.2143,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.28,
    ),
    heroCode: TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 26,
      height: 1.3077,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.0,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    display: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 34,
      height: 1.1765,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.68,
    ),
    headline: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    title: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 15,
      height: 1.3333,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.0,
    ),
    titleSm: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 13,
      height: 1.3846,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.0,
    ),
    body: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 13,
      height: 1.5385,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
    ),
    bodyStrong: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 13,
      height: 1.5385,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0,
    ),
    caption: TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: ['.AppleSystemUIFont', 'Helvetica Neue'],
      fontSize: 12,
      height: 1.3333,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
    ),
    label: TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 11,
      height: 1.2727,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.66,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    code: TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 12,
      height: 1.3333,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    codeLg: TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 15,
      height: 1.3333,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    mono: TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 12.5,
      height: 1.68,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  @override
  XpTypography copyWith({
    TextStyle? hero,
    TextStyle? heroCode,
    TextStyle? display,
    TextStyle? headline,
    TextStyle? title,
    TextStyle? titleSm,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? caption,
    TextStyle? label,
    TextStyle? code,
    TextStyle? codeLg,
    TextStyle? mono,
  }) => XpTypography(
    hero: hero ?? this.hero,
    heroCode: heroCode ?? this.heroCode,
    display: display ?? this.display,
    headline: headline ?? this.headline,
    title: title ?? this.title,
    titleSm: titleSm ?? this.titleSm,
    body: body ?? this.body,
    bodyStrong: bodyStrong ?? this.bodyStrong,
    caption: caption ?? this.caption,
    label: label ?? this.label,
    code: code ?? this.code,
    codeLg: codeLg ?? this.codeLg,
    mono: mono ?? this.mono,
  );

  @override
  XpTypography lerp(XpTypography? other, double t) {
    if (other is! XpTypography) return this;
    return XpTypography(
      hero: TextStyle.lerp(hero, other.hero, t)!,
      heroCode: TextStyle.lerp(heroCode, other.heroCode, t)!,
      display: TextStyle.lerp(display, other.display, t)!,
      headline: TextStyle.lerp(headline, other.headline, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      titleSm: TextStyle.lerp(titleSm, other.titleSm, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      code: TextStyle.lerp(code, other.code, t)!,
      codeLg: TextStyle.lerp(codeLg, other.codeLg, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}

/// Spacing on a 2px sub-grid.
@immutable
class XpSpacing extends ThemeExtension<XpSpacing> {
  const XpSpacing({
    required this.space2,
    required this.space4,
    required this.space6,
    required this.space8,
    required this.space10,
    required this.space12,
    required this.space16,
    required this.space20,
    required this.space24,
    required this.space32,
    required this.space40,
    required this.space48,
  });

  /// `space.2` · --xp-space-2. Icon-to-count gap, badge inner padding.
  final double space2;

  /// `space.4` · --xp-space-4. Icon to label in badges and chips.
  final double space4;

  /// `space.6` · --xp-space-6. Icon to label in rows and buttons; stacked label + value.
  final double space6;

  /// `space.8` · --xp-space-8. Gap between controls in a toolbar group, between chips.
  final double space8;

  /// `space.10` · --xp-space-10. Row inline padding (sidebar, lists), node padding.
  final double space10;

  /// `space.12` · --xp-space-12. Table cell padding, card inner gaps.
  final double space12;

  /// `space.16` · --xp-space-16. Panel padding, gap between toolbar groups.
  final double space16;

  /// `space.20` · --xp-space-20. Content-area side padding, pane header inset.
  final double space20;

  /// `space.24` · --xp-space-24. Gap between stacked panels at comfortable size.
  final double space24;

  /// `space.32` · --xp-space-32. Sheet padding, empty-state stacks.
  final double space32;

  /// `space.40` · --xp-space-40. Dialog padding top.
  final double space40;

  /// `space.48` · --xp-space-48. Empty-state and onboarding outer spacing.
  final double space48;

  static const standard = XpSpacing(
    space2: 2.0,
    space4: 4.0,
    space6: 6.0,
    space8: 8.0,
    space10: 10.0,
    space12: 12.0,
    space16: 16.0,
    space20: 20.0,
    space24: 24.0,
    space32: 32.0,
    space40: 40.0,
    space48: 48.0,
  );

  @override
  XpSpacing copyWith({
    double? space2,
    double? space4,
    double? space6,
    double? space8,
    double? space10,
    double? space12,
    double? space16,
    double? space20,
    double? space24,
    double? space32,
    double? space40,
    double? space48,
  }) => XpSpacing(
    space2: space2 ?? this.space2,
    space4: space4 ?? this.space4,
    space6: space6 ?? this.space6,
    space8: space8 ?? this.space8,
    space10: space10 ?? this.space10,
    space12: space12 ?? this.space12,
    space16: space16 ?? this.space16,
    space20: space20 ?? this.space20,
    space24: space24 ?? this.space24,
    space32: space32 ?? this.space32,
    space40: space40 ?? this.space40,
    space48: space48 ?? this.space48,
  );

  @override
  XpSpacing lerp(XpSpacing? other, double t) {
    if (other is! XpSpacing) return this;
    return XpSpacing(
      space2: lerpDouble(space2, other.space2, t)!,
      space4: lerpDouble(space4, other.space4, t)!,
      space6: lerpDouble(space6, other.space6, t)!,
      space8: lerpDouble(space8, other.space8, t)!,
      space10: lerpDouble(space10, other.space10, t)!,
      space12: lerpDouble(space12, other.space12, t)!,
      space16: lerpDouble(space16, other.space16, t)!,
      space20: lerpDouble(space20, other.space20, t)!,
      space24: lerpDouble(space24, other.space24, t)!,
      space32: lerpDouble(space32, other.space32, t)!,
      space40: lerpDouble(space40, other.space40, t)!,
      space48: lerpDouble(space48, other.space48, t)!,
    );
  }
}

/// Corner radii.
@immutable
class XpRadii extends ThemeExtension<XpRadii> {
  const XpRadii({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.full,
  });

  /// `radius.xs`. Checkbox, meter fills, skeleton bars.
  final double xs;

  /// `radius.sm`. Badges, chips, agent marker, keycaps.
  final double sm;

  /// `radius.md`. Buttons, fields, rows, panels, pipeline nodes.
  final double md;

  /// `radius.lg`. Popovers, menus, sheets, dialogs, toasts, command palette.
  final double lg;

  /// `radius.full`. Toggles, slot dots, progress tracks.
  final double full;

  static const standard = XpRadii(
    xs: 2.0,
    sm: 3.0,
    md: 4.0,
    lg: 8.0,
    full: 999.0,
  );

  @override
  XpRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? full,
  }) => XpRadii(
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    full: full ?? this.full,
  );

  @override
  XpRadii lerp(XpRadii? other, double t) {
    if (other is! XpRadii) return this;
    return XpRadii(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      full: lerpDouble(full, other.full, t)!,
    );
  }
}

/// Stroke widths.
@immutable
class XpBorders extends ThemeExtension<XpBorders> {
  const XpBorders({
    required this.widthHairline,
    required this.widthEmphasis,
    required this.widthFocus,
    required this.focusOffset,
    required this.running,
  });

  /// `border.width.hairline`. Every panel and divider.
  final double widthHairline;

  /// `border.width.emphasis`. Pipeline wires; dashed for not-yet-reached edges.
  final double widthEmphasis;

  /// `border.width.focus`. Focus ring width.
  final double widthFocus;

  /// `border.focus-offset`. Gap between control and focus ring, painted in the surface colour.
  final double focusOffset;

  /// `border.running`. Extra inset ring on a running node (2px total, info.default).
  final double running;

  static const standard = XpBorders(
    widthHairline: 1.0,
    widthEmphasis: 1.5,
    widthFocus: 2.0,
    focusOffset: 2.0,
    running: 1.0,
  );

  @override
  XpBorders copyWith({
    double? widthHairline,
    double? widthEmphasis,
    double? widthFocus,
    double? focusOffset,
    double? running,
  }) => XpBorders(
    widthHairline: widthHairline ?? this.widthHairline,
    widthEmphasis: widthEmphasis ?? this.widthEmphasis,
    widthFocus: widthFocus ?? this.widthFocus,
    focusOffset: focusOffset ?? this.focusOffset,
    running: running ?? this.running,
  );

  @override
  XpBorders lerp(XpBorders? other, double t) {
    if (other is! XpBorders) return this;
    return XpBorders(
      widthHairline: lerpDouble(widthHairline, other.widthHairline, t)!,
      widthEmphasis: lerpDouble(widthEmphasis, other.widthEmphasis, t)!,
      widthFocus: lerpDouble(widthFocus, other.widthFocus, t)!,
      focusOffset: lerpDouble(focusOffset, other.focusOffset, t)!,
      running: lerpDouble(running, other.running, t)!,
    );
  }
}

/// Shadows (light only). In dark, elevation is surface tint: use XpColors.surfaceRaised / surfaceOverlay.
@immutable
class XpElevation extends ThemeExtension<XpElevation> {
  const XpElevation({
    required this.elevation0,
    required this.elevation1,
    required this.elevation2,
    required this.elevation3,
  });

  /// `elevation.0`. Everything on the window: panels are flat with hairlines. No cards inside cards.
  final List<BoxShadow> elevation0;

  /// `elevation.1`. Light only: the selected segmented item and toolbar buttons pressed. Dark: surface.selected tint.
  final List<BoxShadow> elevation1;

  /// `elevation.2`. Popovers, menus, toasts, tooltips. Dark: surface.overlay tint + border.default.
  final List<BoxShadow> elevation2;

  /// `elevation.3`. Sheets, dialogs, command palette. Dark: surface.overlay + border.strong at 1px + scrim behind.
  final List<BoxShadow> elevation3;

  static const light = XpElevation(
    elevation0: <BoxShadow>[],
    elevation1: <BoxShadow>[
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        color: Color.fromRGBO(27, 27, 24, 0.06),
      ),
    ],
    elevation2: <BoxShadow>[
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 6,
        color: Color.fromRGBO(27, 27, 24, 0.08),
      ),
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        color: Color.fromRGBO(27, 27, 24, 0.10),
      ),
    ],
    elevation3: <BoxShadow>[
      BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 12,
        color: Color.fromRGBO(27, 27, 24, 0.10),
      ),
      BoxShadow(
        offset: Offset(0, 24),
        blurRadius: 48,
        color: Color.fromRGBO(27, 27, 24, 0.16),
      ),
    ],
  );

  static const dark = XpElevation(
    elevation0: <BoxShadow>[],
    elevation1: <BoxShadow>[],
    elevation2: <BoxShadow>[],
    elevation3: <BoxShadow>[],
  );

  @override
  XpElevation copyWith({
    List<BoxShadow>? elevation0,
    List<BoxShadow>? elevation1,
    List<BoxShadow>? elevation2,
    List<BoxShadow>? elevation3,
  }) => XpElevation(
    elevation0: elevation0 ?? this.elevation0,
    elevation1: elevation1 ?? this.elevation1,
    elevation2: elevation2 ?? this.elevation2,
    elevation3: elevation3 ?? this.elevation3,
  );

  @override
  XpElevation lerp(XpElevation? other, double t) {
    if (other is! XpElevation) return this;
    return XpElevation(
      elevation0: BoxShadow.lerpList(elevation0, other.elevation0, t)!,
      elevation1: BoxShadow.lerpList(elevation1, other.elevation1, t)!,
      elevation2: BoxShadow.lerpList(elevation2, other.elevation2, t)!,
      elevation3: BoxShadow.lerpList(elevation3, other.elevation3, t)!,
    );
  }
}

/// Sizes and density. `compact` swaps the default row height to 26.
@immutable
class XpSizes extends ThemeExtension<XpSizes> {
  const XpSizes({
    required this.rowDefault,
    required this.rowCompact,
    required this.rowSidebar,
    required this.controlSm,
    required this.controlMd,
    required this.controlLg,
    required this.nodeHeight,
    required this.toolbarHeight,
    required this.sidebarWidth,
    required this.consoleHeight,
    required this.iconXs,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
    required this.iconXl,
  });

  /// `size.row.default`. Default list and table row height (sidebar project rows 40px: two lines).
  final double rowDefault;

  /// `size.row.compact`. Compact density (View ▸ Compact Rows, ⌃⌘=). Tables, log groups, runner lists; never the sidebar.
  final double rowCompact;

  /// `size.row.sidebar`. Sidebar section rows.
  final double rowSidebar;

  /// `size.control.sm`. Inline buttons in rows, keycaps rows, chips.
  final double controlSm;

  /// `size.control.md`. Default buttons, fields, segmented controls, search.
  final double controlMd;

  /// `size.control.lg`. Sheet and dialog footer buttons, the approval hero buttons.
  final double controlLg;

  /// `size.node.height`. Pipeline job node.
  final double nodeHeight;

  /// `size.toolbar.height`. Window title area + toolbar (traffic lights live in it).
  final double toolbarHeight;

  /// `size.sidebar.width`. Sidebar default width; resizable 200–320px.
  final double sidebarWidth;

  /// `size.console.height`. Console default height; min 160px; collapsed strip 34px.
  final double consoleHeight;

  /// `size.icon.xs`. Icons inside type.code and type.label runs.
  final double iconXs;

  /// `size.icon.sm`. Status icons in badges, rows, nodes.
  final double iconSm;

  /// `size.icon.md`. Sidebar, toolbar, buttons.
  final double iconMd;

  /// `size.icon.lg`. Hero status, sheet headers.
  final double iconLg;

  /// `size.icon.xl`. Empty and error states.
  final double iconXl;

  static const standard = XpSizes(
    rowDefault: 32.0,
    rowCompact: 26.0,
    rowSidebar: 28.0,
    controlSm: 24.0,
    controlMd: 28.0,
    controlLg: 32.0,
    nodeHeight: 34.0,
    toolbarHeight: 52.0,
    sidebarWidth: 232.0,
    consoleHeight: 268.0,
    iconXs: 12.0,
    iconSm: 14.0,
    iconMd: 16.0,
    iconLg: 20.0,
    iconXl: 32.0,
  );

  static const compact = XpSizes(
    rowDefault: 26.0,
    rowCompact: 26.0,
    rowSidebar: 28.0,
    controlSm: 24.0,
    controlMd: 28.0,
    controlLg: 32.0,
    nodeHeight: 34.0,
    toolbarHeight: 52.0,
    sidebarWidth: 232.0,
    consoleHeight: 268.0,
    iconXs: 12.0,
    iconSm: 14.0,
    iconMd: 16.0,
    iconLg: 20.0,
    iconXl: 32.0,
  );

  @override
  XpSizes copyWith({
    double? rowDefault,
    double? rowCompact,
    double? rowSidebar,
    double? controlSm,
    double? controlMd,
    double? controlLg,
    double? nodeHeight,
    double? toolbarHeight,
    double? sidebarWidth,
    double? consoleHeight,
    double? iconXs,
    double? iconSm,
    double? iconMd,
    double? iconLg,
    double? iconXl,
  }) => XpSizes(
    rowDefault: rowDefault ?? this.rowDefault,
    rowCompact: rowCompact ?? this.rowCompact,
    rowSidebar: rowSidebar ?? this.rowSidebar,
    controlSm: controlSm ?? this.controlSm,
    controlMd: controlMd ?? this.controlMd,
    controlLg: controlLg ?? this.controlLg,
    nodeHeight: nodeHeight ?? this.nodeHeight,
    toolbarHeight: toolbarHeight ?? this.toolbarHeight,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    consoleHeight: consoleHeight ?? this.consoleHeight,
    iconXs: iconXs ?? this.iconXs,
    iconSm: iconSm ?? this.iconSm,
    iconMd: iconMd ?? this.iconMd,
    iconLg: iconLg ?? this.iconLg,
    iconXl: iconXl ?? this.iconXl,
  );

  @override
  XpSizes lerp(XpSizes? other, double t) {
    if (other is! XpSizes) return this;
    return XpSizes(
      rowDefault: lerpDouble(rowDefault, other.rowDefault, t)!,
      rowCompact: lerpDouble(rowCompact, other.rowCompact, t)!,
      rowSidebar: lerpDouble(rowSidebar, other.rowSidebar, t)!,
      controlSm: lerpDouble(controlSm, other.controlSm, t)!,
      controlMd: lerpDouble(controlMd, other.controlMd, t)!,
      controlLg: lerpDouble(controlLg, other.controlLg, t)!,
      nodeHeight: lerpDouble(nodeHeight, other.nodeHeight, t)!,
      toolbarHeight: lerpDouble(toolbarHeight, other.toolbarHeight, t)!,
      sidebarWidth: lerpDouble(sidebarWidth, other.sidebarWidth, t)!,
      consoleHeight: lerpDouble(consoleHeight, other.consoleHeight, t)!,
      iconXs: lerpDouble(iconXs, other.iconXs, t)!,
      iconSm: lerpDouble(iconSm, other.iconSm, t)!,
      iconMd: lerpDouble(iconMd, other.iconMd, t)!,
      iconLg: lerpDouble(iconLg, other.iconLg, t)!,
      iconXl: lerpDouble(iconXl, other.iconXl, t)!,
    );
  }
}

/// Durations and curves. Use XpMotion.reduced when MediaQuery.disableAnimationsOf(context) is true.
@immutable
class XpMotion extends ThemeExtension<XpMotion> {
  const XpMotion({
    required this.durationInstant,
    required this.durationFast,
    required this.durationBase,
    required this.durationModerate,
    required this.durationSlow,
    required this.durationSpin,
    required this.durationPulse,
    required this.easingStandard,
    required this.easingEnter,
    required this.easingExit,
    required this.easingLinear,
  });

  /// `motion.duration.instant`. Reduce Motion replacement for every non-essential transition.
  final Duration durationInstant;

  /// `motion.duration.fast`. Hover and press fills, toggle thumb, checkbox mark.
  final Duration durationFast;

  /// `motion.duration.base`. Sidebar selection, segmented control thumb, status crossfade.
  final Duration durationBase;

  /// `motion.duration.moderate`. Popover, menu, toast enter; sheet exit.
  final Duration durationModerate;

  /// `motion.duration.slow`. Sheet enter, pipeline progress fill, pane collapse.
  final Duration durationSlow;

  /// `motion.duration.spin`. One turn of the running arc (linear, infinite).
  final Duration durationSpin;

  /// `motion.duration.pulse`. Reconnecting / updating rotation (slower than running so they read differently).
  final Duration durationPulse;

  /// `motion.easing.standard`. Default for moves inside the window. Flutter: Cubic(0.2, 0, 0, 1).
  final Curve easingStandard;

  /// `motion.easing.enter`. Things arriving: sheet, popover, toast. Flutter: Cubic(0.05, 0.7, 0.1, 1).
  final Curve easingEnter;

  /// `motion.easing.exit`. Things leaving. Flutter: Cubic(0.3, 0, 1, 1).
  final Curve easingExit;

  /// `motion.easing.linear`. Spinners and progress that tracks real time. Flutter: Curves.linear.
  final Curve easingLinear;

  static const standard = XpMotion(
    durationInstant: Duration(milliseconds: 0),
    durationFast: Duration(milliseconds: 120),
    durationBase: Duration(milliseconds: 180),
    durationModerate: Duration(milliseconds: 240),
    durationSlow: Duration(milliseconds: 320),
    durationSpin: Duration(milliseconds: 1000),
    durationPulse: Duration(milliseconds: 1600),
    easingStandard: Cubic(0.2, 0, 0, 1),
    easingEnter: Cubic(0.05, 0.7, 0.1, 1),
    easingExit: Cubic(0.3, 0, 1, 1),
    easingLinear: Curves.linear,
  );

  static const reduced = XpMotion(
    durationInstant: Duration.zero,
    durationFast: Duration.zero,
    durationBase: Duration.zero,
    durationModerate: Duration.zero,
    durationSlow: Duration.zero,
    durationSpin: Duration.zero,
    durationPulse: Duration.zero,
    easingStandard: Cubic(0.2, 0, 0, 1),
    easingEnter: Cubic(0.05, 0.7, 0.1, 1),
    easingExit: Cubic(0.3, 0, 1, 1),
    easingLinear: Curves.linear,
  );

  @override
  XpMotion copyWith({
    Duration? durationInstant,
    Duration? durationFast,
    Duration? durationBase,
    Duration? durationModerate,
    Duration? durationSlow,
    Duration? durationSpin,
    Duration? durationPulse,
    Curve? easingStandard,
    Curve? easingEnter,
    Curve? easingExit,
    Curve? easingLinear,
  }) => XpMotion(
    durationInstant: durationInstant ?? this.durationInstant,
    durationFast: durationFast ?? this.durationFast,
    durationBase: durationBase ?? this.durationBase,
    durationModerate: durationModerate ?? this.durationModerate,
    durationSlow: durationSlow ?? this.durationSlow,
    durationSpin: durationSpin ?? this.durationSpin,
    durationPulse: durationPulse ?? this.durationPulse,
    easingStandard: easingStandard ?? this.easingStandard,
    easingEnter: easingEnter ?? this.easingEnter,
    easingExit: easingExit ?? this.easingExit,
    easingLinear: easingLinear ?? this.easingLinear,
  );

  @override
  XpMotion lerp(XpMotion? other, double t) {
    if (other is! XpMotion) return this;
    return XpMotion(
      durationInstant: t < 0.5 ? durationInstant : other.durationInstant,
      durationFast: t < 0.5 ? durationFast : other.durationFast,
      durationBase: t < 0.5 ? durationBase : other.durationBase,
      durationModerate: t < 0.5 ? durationModerate : other.durationModerate,
      durationSlow: t < 0.5 ? durationSlow : other.durationSlow,
      durationSpin: t < 0.5 ? durationSpin : other.durationSpin,
      durationPulse: t < 0.5 ? durationPulse : other.durationPulse,
      easingStandard: t < 0.5 ? easingStandard : other.easingStandard,
      easingEnter: t < 0.5 ? easingEnter : other.easingEnter,
      easingExit: t < 0.5 ? easingExit : other.easingExit,
      easingLinear: t < 0.5 ? easingLinear : other.easingLinear,
    );
  }
}

/// Window sizes and breakpoints.
@immutable
class XpWindow extends ThemeExtension<XpWindow> {
  const XpWindow({
    required this.minWidth,
    required this.minHeight,
    required this.comfortableWidth,
    required this.comfortableHeight,
    required this.largeWidth,
    required this.largeHeight,
    required this.breakpointPipelineVertical,
    required this.breakpointSidebarCollapse,
  });

  /// `window.min.width`. Minimum window width. Sidebar 200px, console collapsed to its strip by default, ledger drops Patches column into the row menu.
  final double minWidth;

  /// `window.min.height`. Minimum window height. Console max 40% of height.
  final double minHeight;

  /// `window.comfortable.width`. Design reference width. Sidebar 232px, horizontal pipeline, console 268px.
  final double comfortableWidth;

  /// `window.comfortable.height`. Design reference height.
  final double comfortableHeight;

  /// `window.large.width`. Large (16-inch MBP default). Content grows; a job view adds the step list beside the log.
  final double largeWidth;

  /// `window.large.height`. Large height. Console 320px.
  final double largeHeight;

  /// `window.breakpoint.pipeline-vertical`. Content width below which the pipeline graph switches to its vertical layout (also the menu bar extra and narrow web).
  final double breakpointPipelineVertical;

  /// `window.breakpoint.sidebar-collapse`. Window width below which the sidebar starts hidden (⌃⌘S to show as overlay).
  final double breakpointSidebarCollapse;

  static const standard = XpWindow(
    minWidth: 1100.0,
    minHeight: 700.0,
    comfortableWidth: 1440.0,
    comfortableHeight: 900.0,
    largeWidth: 1728.0,
    largeHeight: 1117.0,
    breakpointPipelineVertical: 760.0,
    breakpointSidebarCollapse: 1180.0,
  );

  @override
  XpWindow copyWith({
    double? minWidth,
    double? minHeight,
    double? comfortableWidth,
    double? comfortableHeight,
    double? largeWidth,
    double? largeHeight,
    double? breakpointPipelineVertical,
    double? breakpointSidebarCollapse,
  }) => XpWindow(
    minWidth: minWidth ?? this.minWidth,
    minHeight: minHeight ?? this.minHeight,
    comfortableWidth: comfortableWidth ?? this.comfortableWidth,
    comfortableHeight: comfortableHeight ?? this.comfortableHeight,
    largeWidth: largeWidth ?? this.largeWidth,
    largeHeight: largeHeight ?? this.largeHeight,
    breakpointPipelineVertical:
        breakpointPipelineVertical ?? this.breakpointPipelineVertical,
    breakpointSidebarCollapse:
        breakpointSidebarCollapse ?? this.breakpointSidebarCollapse,
  );

  @override
  XpWindow lerp(XpWindow? other, double t) {
    if (other is! XpWindow) return this;
    return XpWindow(
      minWidth: lerpDouble(minWidth, other.minWidth, t)!,
      minHeight: lerpDouble(minHeight, other.minHeight, t)!,
      comfortableWidth: lerpDouble(
        comfortableWidth,
        other.comfortableWidth,
        t,
      )!,
      comfortableHeight: lerpDouble(
        comfortableHeight,
        other.comfortableHeight,
        t,
      )!,
      largeWidth: lerpDouble(largeWidth, other.largeWidth, t)!,
      largeHeight: lerpDouble(largeHeight, other.largeHeight, t)!,
      breakpointPipelineVertical: lerpDouble(
        breakpointPipelineVertical,
        other.breakpointPipelineVertical,
        t,
      )!,
      breakpointSidebarCollapse: lerpDouble(
        breakpointSidebarCollapse,
        other.breakpointSidebarCollapse,
        t,
      )!,
    );
  }
}

/// The semantic pair a status uses.
enum XpStatusPair {
  neutral,
  info,
  attention,
  positive,
  negative,
  caution,
  merged,
}

/// How a status moves. Reduce Motion: spin → static arc with centre dot; turn → static icon.
enum XpStatusMotion { none, spin, turn }

/// Every status in PRODUCT.md §5 with its label, icon and pair.
enum XpStatus {
  jobQueued(
    'Queued',
    XpStatusPair.neutral,
    PhosphorIconsRegular.circleDashed,
    XpStatusMotion.none,
  ),
  jobWaitingRunner(
    'Waiting for runner',
    XpStatusPair.neutral,
    PhosphorIconsRegular.hourglassMedium,
    XpStatusMotion.none,
  ),
  jobWaitingApproval(
    'Waiting for approval',
    XpStatusPair.attention,
    PhosphorIconsRegular.handPalm,
    XpStatusMotion.none,
  ),
  jobRunning(
    'Running',
    XpStatusPair.info,
    PhosphorIconsRegular.circleNotch,
    XpStatusMotion.spin,
  ),
  jobSucceeded(
    'Succeeded',
    XpStatusPair.positive,
    PhosphorIconsRegular.checkCircle,
    XpStatusMotion.none,
  ),
  jobFailed(
    'Failed',
    XpStatusPair.negative,
    PhosphorIconsRegular.xCircle,
    XpStatusMotion.none,
  ),
  jobCancelled(
    'Cancelled',
    XpStatusPair.neutral,
    PhosphorIconsRegular.stopCircle,
    XpStatusMotion.none,
  ),
  jobSkipped(
    'Skipped · already done',
    XpStatusPair.neutral,
    PhosphorIconsRegular.skipForwardCircle,
    XpStatusMotion.none,
  ),
  jobInterrupted(
    'Interrupted',
    XpStatusPair.caution,
    PhosphorIconsRegular.pauseCircle,
    XpStatusMotion.none,
  ),
  releaseDraft(
    'Draft',
    XpStatusPair.neutral,
    PhosphorIconsRegular.pencilSimple,
    XpStatusMotion.none,
  ),
  releaseBuilding(
    'Building',
    XpStatusPair.info,
    PhosphorIconsRegular.circleNotch,
    XpStatusMotion.spin,
  ),
  releaseUploaded(
    'Uploaded',
    XpStatusPair.neutral,
    PhosphorIconsRegular.uploadSimple,
    XpStatusMotion.none,
  ),
  releaseInReview(
    'In review',
    XpStatusPair.info,
    PhosphorIconsRegular.eye,
    XpStatusMotion.none,
  ),
  releaseRejected(
    'Rejected',
    XpStatusPair.negative,
    PhosphorIconsRegular.xCircle,
    XpStatusMotion.none,
  ),
  releaseApproved(
    'Approved',
    XpStatusPair.positive,
    PhosphorIconsRegular.check,
    XpStatusMotion.none,
  ),
  releaseLive(
    'Live',
    XpStatusPair.positive,
    PhosphorIconsRegular.radioButton,
    XpStatusMotion.none,
  ),
  releaseMerged(
    'Merged',
    XpStatusPair.merged,
    PhosphorIconsRegular.gitMerge,
    XpStatusMotion.none,
  ),
  releaseAbandoned(
    'Abandoned',
    XpStatusPair.neutral,
    PhosphorIconsRegular.archive,
    XpStatusMotion.none,
  ),
  appstoreProcessing(
    'Processing',
    XpStatusPair.neutral,
    PhosphorIconsRegular.hourglassMedium,
    XpStatusMotion.none,
  ),
  appstoreReadyToSubmit(
    'Ready to submit',
    XpStatusPair.attention,
    PhosphorIconsRegular.paperPlaneTilt,
    XpStatusMotion.none,
  ),
  appstoreWaitingReview(
    'Waiting for review',
    XpStatusPair.neutral,
    PhosphorIconsRegular.clock,
    XpStatusMotion.none,
  ),
  appstoreInReview(
    'In review',
    XpStatusPair.info,
    PhosphorIconsRegular.eye,
    XpStatusMotion.none,
  ),
  appstorePendingRelease(
    'Pending developer release',
    XpStatusPair.attention,
    PhosphorIconsRegular.handPalm,
    XpStatusMotion.none,
  ),
  appstoreRejected(
    'Rejected',
    XpStatusPair.negative,
    PhosphorIconsRegular.xCircle,
    XpStatusMotion.none,
  ),
  appstoreLive(
    'Ready for sale',
    XpStatusPair.positive,
    PhosphorIconsRegular.radioButton,
    XpStatusMotion.none,
  ),
  appstorePhased(
    'Phased rollout · day 3 of 7',
    XpStatusPair.positive,
    PhosphorIconsRegular.radioButton,
    XpStatusMotion.none,
  ),
  appstoreUnknown(
    'Unknown · live 5.3.6',
    XpStatusPair.neutral,
    PhosphorIconsRegular.question,
    XpStatusMotion.none,
  ),
  playDraft(
    'Draft',
    XpStatusPair.neutral,
    PhosphorIconsRegular.pencilSimple,
    XpStatusMotion.none,
  ),
  playNotSent(
    'Not sent for review',
    XpStatusPair.attention,
    PhosphorIconsRegular.paperPlaneTilt,
    XpStatusMotion.none,
  ),
  playInReview(
    'In review',
    XpStatusPair.info,
    PhosphorIconsRegular.eye,
    XpStatusMotion.none,
  ),
  playApprovedUnpublished(
    'Approved · not published',
    XpStatusPair.attention,
    PhosphorIconsRegular.handPalm,
    XpStatusMotion.none,
  ),
  playNotApproved(
    'Not approved',
    XpStatusPair.negative,
    PhosphorIconsRegular.xCircle,
    XpStatusMotion.none,
  ),
  playLive(
    'Published',
    XpStatusPair.positive,
    PhosphorIconsRegular.radioButton,
    XpStatusMotion.none,
  ),
  playRollingOut(
    'Rolling out · 20%',
    XpStatusPair.positive,
    PhosphorIconsRegular.radioButton,
    XpStatusMotion.none,
  ),
  playUnknown(
    'Unknown · live 5.3.7',
    XpStatusPair.neutral,
    PhosphorIconsRegular.question,
    XpStatusMotion.none,
  ),
  firebaseUploaded(
    'Uploaded',
    XpStatusPair.neutral,
    PhosphorIconsRegular.uploadSimple,
    XpStatusMotion.none,
  ),
  firebaseDistributed(
    'Distributed · 2 groups',
    XpStatusPair.positive,
    PhosphorIconsRegular.usersThree,
    XpStatusMotion.none,
  ),
  approvalPending(
    'Pending',
    XpStatusPair.attention,
    PhosphorIconsRegular.handPalm,
    XpStatusMotion.none,
  ),
  approvalApproved(
    'Approved',
    XpStatusPair.positive,
    PhosphorIconsRegular.check,
    XpStatusMotion.none,
  ),
  approvalDenied(
    'Denied',
    XpStatusPair.negative,
    PhosphorIconsRegular.prohibit,
    XpStatusMotion.none,
  ),
  approvalExpired(
    'Expired',
    XpStatusPair.neutral,
    PhosphorIconsRegular.clockCountdown,
    XpStatusMotion.none,
  ),
  runnerIdle(
    'Online · idle',
    XpStatusPair.positive,
    PhosphorIconsRegular.checkCircle,
    XpStatusMotion.none,
  ),
  runnerBusy(
    'Online · busy 2/3',
    XpStatusPair.info,
    PhosphorIconsRegular.circleNotch,
    XpStatusMotion.spin,
  ),
  runnerOffline(
    'Offline',
    XpStatusPair.neutral,
    PhosphorIconsRegular.circleDashed,
    XpStatusMotion.none,
  ),
  runnerLost(
    'Lost mid-job',
    XpStatusPair.negative,
    PhosphorIconsRegular.warningCircle,
    XpStatusMotion.none,
  ),
  runnerUpdating(
    'Updating',
    XpStatusPair.info,
    PhosphorIconsRegular.arrowsClockwise,
    XpStatusMotion.turn,
  ),
  engineConnected(
    'Connected',
    XpStatusPair.positive,
    PhosphorIconsRegular.plugsConnected,
    XpStatusMotion.none,
  ),
  engineReconnecting(
    'Reconnecting',
    XpStatusPair.caution,
    PhosphorIconsRegular.arrowsClockwise,
    XpStatusMotion.turn,
  ),
  engineUnreachable(
    'Unreachable · cached',
    XpStatusPair.negative,
    PhosphorIconsRegular.cloudSlash,
    XpStatusMotion.none,
  ),
  engineSecretsLocked(
    'Secrets locked',
    XpStatusPair.attention,
    PhosphorIconsRegular.lockSimple,
    XpStatusMotion.none,
  ),
  scanError(
    'Error',
    XpStatusPair.negative,
    PhosphorIconsRegular.xCircle,
    XpStatusMotion.none,
  ),
  scanWarning(
    'Warning',
    XpStatusPair.caution,
    PhosphorIconsRegular.warning,
    XpStatusMotion.none,
  ),
  scanInfo(
    'Info',
    XpStatusPair.info,
    PhosphorIconsRegular.info,
    XpStatusMotion.none,
  ),
  credentialVerified(
    'Verified',
    XpStatusPair.positive,
    PhosphorIconsRegular.sealCheck,
    XpStatusMotion.none,
  ),
  credentialExpiring(
    'Expiring in 12 days',
    XpStatusPair.caution,
    PhosphorIconsRegular.clockCountdown,
    XpStatusMotion.none,
  ),
  credentialExpired(
    'Expired',
    XpStatusPair.negative,
    PhosphorIconsRegular.sealWarning,
    XpStatusMotion.none,
  ),
  credentialMissing(
    'Missing',
    XpStatusPair.caution,
    PhosphorIconsRegular.key,
    XpStatusMotion.none,
  );

  const XpStatus(this.label, this.pair, this.icon, this.motion);
  final String label;
  final XpStatusPair pair;
  final IconData icon;
  final XpStatusMotion motion;
}

extension XpStatusColors on XpColors {
  Color container(XpStatusPair p) => switch (p) {
    XpStatusPair.neutral => statusNeutralContainer,
    XpStatusPair.info => statusInfoContainer,
    XpStatusPair.attention => statusAttentionContainer,
    XpStatusPair.positive => statusPositiveContainer,
    XpStatusPair.negative => statusNegativeContainer,
    XpStatusPair.caution => statusCautionContainer,
    XpStatusPair.merged => statusMergedContainer,
  };
  Color onContainer(XpStatusPair p) => switch (p) {
    XpStatusPair.neutral => statusNeutralOnContainer,
    XpStatusPair.info => statusInfoOnContainer,
    XpStatusPair.attention => statusAttentionOnContainer,
    XpStatusPair.positive => statusPositiveOnContainer,
    XpStatusPair.negative => statusNegativeOnContainer,
    XpStatusPair.caution => statusCautionOnContainer,
    XpStatusPair.merged => statusMergedOnContainer,
  };
}

/// Registers every XPath extension on a ThemeData.
ThemeData xpTheme(
  Brightness b, {
  bool compact = false,
  bool reduceMotion = false,
}) {
  final dark = b == Brightness.dark;
  final c = dark ? XpColors.dark : XpColors.light;
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: c.surfaceWindow,
    fontFamily: 'IBM Plex Sans',
    focusColor: c.focusRing,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: c.selectionDefault,
      cursorColor: c.accentDefault,
    ),
    extensions: [
      c,
      XpTypography.standard,
      XpSpacing.standard,
      XpRadii.standard,
      XpBorders.standard,
      dark ? XpElevation.dark : XpElevation.light,
      compact ? XpSizes.compact : XpSizes.standard,
      reduceMotion ? XpMotion.reduced : XpMotion.standard,
      XpWindow.standard,
    ],
  );
}

extension XpThemeX on BuildContext {
  XpColors get xpColors => Theme.of(this).extension<XpColors>()!;
  XpTypography get xpType => Theme.of(this).extension<XpTypography>()!;
  XpSpacing get xpSpace => Theme.of(this).extension<XpSpacing>()!;
  XpRadii get xpRadii => Theme.of(this).extension<XpRadii>()!;
  XpSizes get xpSizes => Theme.of(this).extension<XpSizes>()!;
  XpMotion get xpMotion => Theme.of(this).extension<XpMotion>()!;
}
