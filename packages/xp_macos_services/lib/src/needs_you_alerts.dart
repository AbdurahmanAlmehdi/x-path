import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

/// The name of the platform channel of the notifications and the menu bar
/// extra (`MacosServicesChannel.swift`, ADR 0005).
const needsYouChannelName = 'ly.abdurahman.xpath/needs_you';

/// A macOS notification of an approval that waits
/// (`Approval-Notification.dc.html`). Its buttons are [review] and [later];
/// neither approves anything.
class ApprovalNotice extends Equatable {
  /// Creates the notice.
  const new({
    required this.approvalId,
    required this.title,
    required this.body,
    required this.review,
    required this.later,
  });

  /// The approval; it also names the notification, so it can be withdrawn.
  final String approvalId;

  /// One line: what is asked.
  final String title;

  /// Where: the project, flavor, commit and expiry.
  final String body;

  /// The label of the button that opens the confirmation sheet ("Review…").
  final String review;

  /// The label of the button that dismisses it ("Later").
  final String later;

  @override
  List<Object?> get props => [approvalId, title, body, review, later];
}

/// One approval in the menu bar extra.
class MenuBarItem extends Equatable {
  /// Creates the item.
  const new({
    required this.approvalId,
    required this.title,
    required this.detail,
  });

  /// The approval the item opens.
  final String approvalId;

  /// What is asked, for example `Review: Submit 5.4.1 (3283)…`.
  final String title;

  /// Where, for example `mataa_new_app · prod · 9a3bc0d · 23h 51m left`.
  final String detail;

  @override
  List<Object?> get props => [approvalId, title, detail];
}

/// What the menu bar extra shows (`MenuBar-Extra.dc.html`): its icon (with
/// a dot while something [needsYou]) and its menu. Every string is
/// localized by the app.
class MenuBarContent extends Equatable {
  /// Creates the content.
  const new({
    required this.tooltip,
    required this.header,
    required this.items,
    required this.openApp,
  });

  /// The tooltip of the icon, for example `XPath: 1 needs you`.
  final String tooltip;

  /// The first, disabled line of the menu: `Needs you · 1`, or that nothing
  /// does.
  final String header;

  /// The approvals that wait, each opening its confirmation sheet.
  final List<MenuBarItem> items;

  /// The label of the item that brings the window forward ("Open XPath").
  final String openApp;

  /// Whether something waits for the owner.
  bool get needsYou => items.isNotEmpty;

  /// The form the channel sends.
  Map<String, Object?> toMap() => {
    'tooltip': tooltip,
    'header': header,
    'needsYou': needsYou,
    'openApp': openApp,
    'items': [
      for (final item in items)
        {'id': item.approvalId, 'title': item.title, 'detail': item.detail},
    ],
  };

  @override
  List<Object?> get props => [tooltip, header, items, openApp];
}

/// What the owner did with a notification or the menu bar extra. None of it
/// decides an approval: that happens only in the confirmation sheet of the
/// main window (DECISIONS.md).
sealed class NeedsYouAction extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// "Review…": open the confirmation sheet of [approvalId] in the main
/// window.
final class ReviewApproval extends NeedsYouAction {
  /// Creates the action.
  const new(this.approvalId);

  /// The approval.
  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
}

/// The notification itself was clicked: show [approvalId] in the inbox.
final class ShowApproval extends NeedsYouAction {
  /// Creates the action.
  const new(this.approvalId);

  /// The approval.
  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
}

/// "Open XPath": bring the window forward.
final class OpenApp extends NeedsYouAction {
  /// Creates the action.
  const new();
}

/// Tells the owner, outside the window, that an approval waits: macOS
/// notifications and the menu bar extra.
abstract interface class NeedsYouAlerts {
  /// Shows [notice]. The first notice asks macOS for permission to notify;
  /// nothing is shown if the owner refused.
  Future<void> notify(ApprovalNotice notice);

  /// Takes the notification of [approvalId] away (it was decided).
  Future<void> withdraw(String approvalId);

  /// Shows the menu bar extra with [content].
  Future<void> updateMenuBar(MenuBarContent content);

  /// What the owner did with a notification or the menu.
  Stream<NeedsYouAction> get actions;
}

/// [NeedsYouAlerts] over the platform channel of the macOS runner.
class MethodChannelNeedsYouAlerts implements NeedsYouAlerts {
  /// Creates the alerts over [channel] and starts listening to it.
  new({this.channel = const MethodChannel(needsYouChannelName)}) {
    channel.setMethodCallHandler(_handle);
  }

  /// The channel.
  final MethodChannel channel;

  final _actions = StreamController<NeedsYouAction>.broadcast();

  Future<void> _handle(MethodCall call) async {
    final arguments = call.arguments;
    final id = arguments is Map ? arguments['id'] as String? : null;
    final action = switch ((call.method, id)) {
      ('review', final String id) => ReviewApproval(id),
      ('show', final String id) => ShowApproval(id),
      ('open', _) => const OpenApp(),
      _ => null,
    };
    if (action != null) _actions.add(action);
  }

  @override
  Future<void> notify(ApprovalNotice notice) =>
      channel.invokeMethod<void>('notify', {
        'id': notice.approvalId,
        'title': notice.title,
        'body': notice.body,
        'review': notice.review,
        'later': notice.later,
      });

  @override
  Future<void> withdraw(String approvalId) =>
      channel.invokeMethod<void>('withdraw', {'id': approvalId});

  @override
  Future<void> updateMenuBar(MenuBarContent content) =>
      channel.invokeMethod<void>('menuBar', content.toMap());

  @override
  Stream<NeedsYouAction> get actions => _actions.stream;
}
