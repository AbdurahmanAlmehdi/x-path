import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// Something to tell the owner: the content of one notification, before it
/// goes out as a `notification.raised` event and as a Slack message.
class Notice extends Equatable {
  /// Creates a notice.
  ///
  /// [key] says what the notice is about: the same key within a short time is
  /// the same notice (a flapping state) and is sent once.
  const new({
    required this.kind,
    required this.level,
    required this.title,
    required this.body,
    required this.key,
    this.projectId,
    this.releaseId,
    this.jobId,
    this.approvalId,
  });

  /// What it is about.
  final NotificationKind kind;

  /// How much it matters.
  final NotificationLevel level;

  /// One line.
  final String title;

  /// The details.
  final String body;

  /// What identifies the notice for de-duplication.
  final String key;

  /// The project it is about.
  final String? projectId;

  /// The release it is about.
  final String? releaseId;

  /// The job it is about.
  final String? jobId;

  /// The approval it is about.
  final String? approvalId;

  /// The event that tells the app.
  NotificationRaised toEvent() => NotificationRaised(
    kind: kind,
    level: level,
    title: title,
    body: body,
    projectId: projectId,
    releaseId: releaseId,
    jobId: jobId,
    approvalId: approvalId,
  );

  /// The message for Slack: the title in bold, then the body, with the
  /// characters Slack reads as markup escaped.
  String get slackText => '*${_escape(title)}*\n${_escape(body)}';

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  List<Object?> get props => [
    kind,
    level,
    title,
    body,
    key,
    projectId,
    releaseId,
    jobId,
    approvalId,
  ];
}
