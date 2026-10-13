import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/altool_fixtures.dart';

void main() {
  group('an upload that went through', () {
    final output = AltoolOutput.parse(
      altoolFixture('altool_upload_succeeded.txt'),
    );

    test('is confirmed and has no errors', () {
      expect(output.rejected, isFalse);
      expect(output.confirmed, isTrue);
      expect(output.errors, isEmpty);
    });

    test('has the delivery id', () {
      expect(output.deliveryId, '3d6a9d4a-8f0e-4a62-9d8b-1c2f5b7e9a10');
    });

    test('is not rejected by the warning it printed', () {
      expect(output.hint, isNull);
    });
  });

  group('a rejection that exited 0 (closed train)', () {
    final output = AltoolOutput.parse(
      altoolFixture('altool_closed_train_exit0.txt'),
    );

    test('is rejected', () {
      expect(output.rejected, isTrue);
      expect(output.confirmed, isFalse);
    });

    test('reports the error lines and the ITMS code once', () {
      expect(output.errors, hasLength(3));
      expect(output.errors.first, '*** Error: Validation failed (409)');
      expect(output.codes, ['90186']);
    });

    test('says to bump the version', () {
      expect(output.hint, contains('Bump the version'));
    });

    test('describes the first lines', () {
      expect(output.describe(limit: 1), contains('(+2 more)'));
      expect(output.describe(), isNot(contains('more)')));
    });
  });

  group('an error of altool 27', () {
    test('is rejected: a missing key file', () {
      final output = AltoolOutput.parse(
        altoolFixture('altool27_missing_key.txt'),
      );

      expect(output.rejected, isTrue);
      expect(output.codes, isEmpty);
      expect(output.errors.single, contains('Failed to load AuthKey file'));
      expect(output.hint, contains('refused the credentials'));
    });

    test('is rejected: a missing IPA, with two error lines', () {
      final output = AltoolOutput.parse(
        altoolFixture('altool27_missing_ipa.txt'),
      );

      expect(output.rejected, isTrue);
      expect(output.errors, hasLength(2));
      expect(output.errors.last, endsWith('ExitFailure (31)'));
      expect(output.hint, isNull);
    });

    test('is rejected: a build number used before', () {
      final output = AltoolOutput.parse(
        altoolFixture('altool_redundant_binary.txt'),
      );

      expect(output.codes, ['90189']);
      expect(output.hint, contains('Allocate a new build number'));
    });

    test('is rejected: authentication', () {
      final output = AltoolOutput.parse(
        altoolFixture('altool_authentication_failed.txt'),
      );

      expect(output.rejected, isTrue);
      expect(output.hint, contains('Apple ID'));
    });
  });

  group('the markers of the reference scripts', () {
    for (final line in [
      'ERROR: something',
      '*** Error: something',
      'Validation failed for the package',
      'UPLOAD FAILED with 1 errors',
      'VALIDATION_ERROR',
      'The upload failed.',
      'Failed to upload package.',
      'Failed to validate package.',
      'Unable to authenticate.',
      'ERROR ITMS-90062: "This bundle is invalid."',
    ]) {
      test('reject "$line"', () {
        expect(AltoolOutput.parse([line]).rejected, isTrue);
      });
    }

    test('ITMS-90062 gets the train hint', () {
      final output = AltoolOutput.parse(const ['ERROR ITMS-90062: "invalid"']);

      expect(output.hint, contains('train is closed'));
    });

    for (final line in [
      'No errors uploading /work/app.ipa',
      'UPLOAD SUCCEEDED with no errors',
      'Upload succeeded.',
      "Package 'a.ipa' upload complete.",
    ]) {
      test('confirm "$line"', () {
        final output = AltoolOutput.parse([line]);

        expect(output.confirmed, isTrue);
        expect(output.rejected, isFalse);
      });
    }

    test('ignore warnings, blank lines and plain text', () {
      final output = AltoolOutput.parse(const [
        '',
        '   ',
        'WARNING ITMS-90000: "careful"',
        'Uploading',
      ]);

      expect(output.rejected, isFalse);
      expect(output.confirmed, isFalse);
      expect(output.deliveryId, isNull);
    });

    test('read the delivery id from Delivery ID too', () {
      final output = AltoolOutput.parse(const [
        'Delivery ID: 3d6a9d4a-8f0e-4a62-9d8b-1c2f5b7e9a10',
      ]);

      expect(output.deliveryId, '3d6a9d4a-8f0e-4a62-9d8b-1c2f5b7e9a10');
    });
  });

  test('a clean output equals another clean output', () {
    expect(AltoolOutput.parse(const []), const AltoolOutput());
  });
}
