/// What a notification is about.
enum NotificationKind {
  /// A production job failed.
  jobFailed('job_failed'),

  /// A production job succeeded.
  jobSucceeded('job_succeeded'),

  /// An action waits for the owner's approval (D-13).
  approvalRequested('approval_requested'),

  /// The owner approved or denied an action.
  approvalDecided('approval_decided'),

  /// An approval ran out of time and counts as denied.
  approvalExpired('approval_expired'),

  /// A store rejected a release.
  releaseRejected('release_rejected'),

  /// The stores approved a release.
  releaseApproved('release_approved'),

  /// A release is on sale in every store it targets.
  releaseLive('release_live'),

  /// The pull request of a release was merged.
  releaseMerged('release_merged'),

  /// A credential that worked is refused now.
  credentialExpired('credential_expired'),

  /// The engine cannot reach its secrets (D-10).
  secretsLocked('secrets_locked'),

  /// A build is live in a store: if it is a forced update, the minimum
  /// version in Remote Config can be raised now.
  minVersionReminder('min_version_reminder');

  new(this.wire);

  /// The name on the wire.
  final String wire;

  /// The kind named [wire], or `null` for a name this version does not know.
  static NotificationKind? fromWire(String wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// How much a notification matters.
enum NotificationLevel {
  /// Good to know.
  info('info'),

  /// Something went well.
  success('success'),

  /// The owner should look at it.
  warning('warning'),

  /// Something failed.
  error('error');

  new(this.wire);

  /// The name on the wire.
  final String wire;

  /// The level named [wire], or `null` for a name this version does not know.
  static NotificationLevel? fromWire(String wire) {
    for (final level in values) {
      if (level.wire == wire) return level;
    }
    return null;
  }
}
