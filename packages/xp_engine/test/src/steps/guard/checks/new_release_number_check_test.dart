import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  const check = NewReleaseNumberCheck();

  test('names itself newReleaseNumber', () {
    expect(check.name, GuardCheckName.newReleaseNumber);
  });

  GuardRequest request(
    List<GitTagInfo> tags, {
    String version = '5.4.1+3283',
  }) => guardRequest(
    files: customerApp(version),
    git: guardRequest().git..tags.addAll(tags),
  ).request;

  test('passes for a version higher than every release', () async {
    final result = await check.run(
      request([tag('v5.4.0+3282'), tag('v5.3.0+3100'), tag('archive/x')]),
    );

    expect(result.status, GuardStatus.passed);
    expect(result.message, '5.4.1 is higher than the last release, 5.4.0.');
  });

  test('passes for the first release', () async {
    final result = await check.run(request([]));

    expect(result.status, GuardStatus.passed);
    expect(result.message, '5.4.1 is the first release.');
  });

  test('passes for the other platform of the same release', () async {
    final result = await check.run(
      request([tag('v5.4.0+3282'), tag('v5.4.1+3283', dispatchedSha)]),
    );

    expect(result.status, GuardStatus.passed);
  });

  // Incident: 5.4.0 had shipped as v5.4.0+3282; a second release of 5.4.0
  // would make the ledger ambiguous and leave the first unpatchable
  // (R:157-163).
  test(
    'fails for a version that was released before (real incident)',
    () async {
      final result = await check.run(
        request([tag('v5.4.0+3282')], version: '5.4.0+3290'),
      );

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'v5.4.0+3282 already exists, so 5.4.0 has shipped before.',
      );
      expect(result.fix, contains('Bump to a higher version'));
    },
  );

  test('fails when the same version is tagged on another commit', () async {
    final result = await check.run(request([tag('v5.4.1+3283', otherSha)]));

    expect(result.status, GuardStatus.failed);
  });

  test(
    'fails when the same version has another build on this commit',
    () async {
      final result = await check.run(
        request([tag('v5.4.1+3280', dispatchedSha)]),
      );

      expect(result.status, GuardStatus.failed);
    },
  );

  test('fails for a version a patch tag shows was released', () async {
    final result = await check.run(request([tag('v5.4.1+3283-p1')]));

    expect(result.status, GuardStatus.failed);
  });

  test('fails for a version below the last release', () async {
    final result = await check.run(
      request([tag('v5.5.0+3300'), tag('v5.3.0+3100')], version: '5.4.2+3301'),
    );

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      '5.4.2 is not higher than 5.5.0, which was released before.',
    );
    expect(result.fix, 'Bump to a version higher than 5.5.0.');
  });

  test('looks only at the tags of its own app', () async {
    final result = await check.run(
      guardRequest(
        files: customerApp('1.0.0+8'),
        git: guardRequest().git
          ..tags.addAll([
            tag('web/prod/v9.0.0+1'),
            tag('mobile/prod/v0.9.0+7'),
          ]),
        model: const ReleaseModel(
          tagPattern: '{app}/{flavor}/v{version}+{build}',
        ),
        scope: const TagScope(app: 'mobile', flavor: 'prod'),
      ).request,
    );

    expect(result.status, GuardStatus.passed);
  });
}
