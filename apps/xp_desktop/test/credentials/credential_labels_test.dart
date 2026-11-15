import 'package:flutter_test/flutter_test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/widgets/credential_labels.dart';
import 'package:xp_desktop/l10n/gen/app_localizations_en.dart';

void main() {
  group('certificateName', () {
    final l10n = AppLocalizationsEn();

    test('names the identity after the project and the flavor', () {
      expect(
        certificateName(l10n, 'octo/app', 'prod'),
        'Apple Distribution · octo/app prod',
      );
    });

    test('keeps only the last part of a folder too long for a name', () {
      final folder = '/Users/sam/${'work/' * 12}mataa';

      final name = certificateName(l10n, folder, 'prod');

      expect(name, 'Apple Distribution · mataa prod');
      expect(credentialName(name), name);
    });

    test('cuts a name that is too long even so at the limit', () {
      final name = certificateName(l10n, '/work/${'m' * 90}', 'prod');

      expect(name, hasLength(maxCredentialNameLength));
      expect(name, startsWith('Apple Distribution · mmm'));
    });
  });
}
