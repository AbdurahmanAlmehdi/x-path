import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';

/// Fails the job before a build starts when a credential it needs is not
/// assigned to the flavor, or was refused at its last check: an expired or
/// revoked ASC key, a revoked app-specific password, a deleted service
/// account, a key that cannot see the flavor's app (D-22 preflight).
///
/// It reads what the checks recorded (on save, on assignment, on request and
/// the daily health check), of the credential the flavor uses and of the
/// assignment, and asks nobody, so preflight stays fast. A credential that
/// could not be checked, or never was, is a warning: only a store's "no"
/// stops a release.
class CredentialsCheck extends GuardCheck {
  /// Creates the check over the recorded [_credentials].
  const new(this._credentials);

  final CredentialRepository _credentials;

  @override
  GuardCheckName get name => GuardCheckName.credentials;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final flavorId = request.input.flavorId;
    if (flavorId == null) {
      return skipped('The job names no flavor, so there is nothing to check.');
    }
    final records = await _credentials.assignments(flavorId: flavorId);
    final needed = request.input.credentialKinds;
    final missing = [
      for (final kind in needed)
        if (records.every((record) => record.kind != kind)) kind,
    ];
    final used = [
      for (final record in records)
        if (needed.isEmpty || needed.contains(record.kind)) record,
    ];

    final failures = <String>[
      for (final kind in missing)
        '${kind.wire}: no credential is assigned to the flavor.',
      for (final record in used)
        if (record.status == CredentialStatus.rejected)
          '${_label(record)}: ${_why(record)}',
    ];
    if (failures.isNotEmpty) {
      return failed(failures.join(' '), fix: _fixes(missing, used));
    }
    final unsure = [
      for (final record in used)
        if (record.status != CredentialStatus.verified) record,
    ];
    if (unsure.isNotEmpty) {
      return warned(
        'Not confirmed: ${unsure.map(_unsure).join(', ')}.',
        fix:
            'Check them again: xp credentials verify <name> '
            '(POST /credentials/{credentialId}/verify).',
      );
    }
    if (used.isEmpty) return skipped('The flavor needs no credentials.');
    return passed(
      '${used.length} credential${used.length == 1 ? '' : 's'} accepted at '
      'the last check.',
    );
  }

  String _fixes(List<CredentialKind> missing, List<AssignedCredential> used) {
    final kinds = missing.map((kind) => kind.wire).join(', ');
    final assign =
        'Assign a credential of $kinds to the flavor: xp credentials assign, '
        'or PUT /projects/{id}/flavors/{flavor}/credentials/{kind}.';
    final fixes = [
      if (missing.isNotEmpty) assign,
      for (final record in used)
        if (record.status == CredentialStatus.rejected && record.fix != null)
          '${record.kind.wire}: ${record.fix}',
    ];
    return fixes.join(' ');
  }

  String _label(AssignedCredential record) =>
      '${record.kind.wire} "${record.credential.name}"';

  String _why(AssignedCredential record) =>
      record.message ?? 'refused at the last check.';

  String _unsure(AssignedCredential record) {
    final why = record.status == CredentialStatus.unverified
        ? 'never checked'
        : 'could not be reached';
    return '${_label(record)} ($why)';
  }
}
