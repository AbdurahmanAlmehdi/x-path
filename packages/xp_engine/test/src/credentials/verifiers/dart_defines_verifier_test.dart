import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const verifier = DartDefinesVerifier();
  const target = CredentialTarget();

  test('checks the dart-define kind on its own', () {
    expect(verifier.kind, CredentialKind.dartDefines);
    expect(verifier.checksTarget, isFalse);
  });

  test('accepts a file Flutter can read', () async {
    expect(
      await verifier.verify(const DartDefinesMaterial('A=x\n'), target),
      const VerificationResult.verified(),
    );
  });

  test('rejects a stored file that is not one, without quoting it', () async {
    final result = await verifier.verify(
      const DartDefinesMaterial('secret-value\n'),
      target,
    );

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, isNot(contains('secret-value')));
  });
}
