import 'package:test/test.dart';
import 'package:xp_engine/src/dispatch/skip_reason.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  String reason(
    String condition,
    Map<String, Object?> scope, {
    String? flavor,
  }) => skipReason(Expression.parse(condition), scope, flavor: flavor);

  const upload =
      "(platform == 'android' && (inputs.firebaseAppIds[flavor.name].android "
      '|| flavor.firebaseAppId.android)) || '
      "(platform == 'ios' && (inputs.appleAppIds[flavor.name] || "
      'flavor.appleAppId))';

  Map<String, Object?> cell(String platform) => {
    'platform': platform,
    'inputs': const <String, Object?>{},
    'flavor': const {'name': 'dev', 'firebaseAppId': <String, Object?>{}},
  };

  test('names the app id an upload lacks, not the other platform', () {
    expect(
      reason(upload, cell('android'), flavor: 'dev'),
      'no Firebase app id for dev',
    );
    expect(
      reason(upload, cell('ios'), flavor: 'dev'),
      'no App Store app id for dev',
    );
  });

  test('says what a flavor lacks or has', () {
    const scope = {
      'inputs': <String, Object?>{},
      'flavor': {
        'name': 'prod',
        'shorebird': false,
        'prod': true,
        'credentials': <String, Object?>{'play_sa': true},
      },
    };
    expect(
      reason('flavor.credentials.asc_key', scope),
      'no asc_key credential',
    );
    expect(
      reason('!flavor.credentials.play_sa', scope),
      'it has a play_sa credential',
    );
    expect(reason('flavor.shorebird', scope), 'not a Shorebird flavor');
    expect(reason('!flavor.prod', scope), 'a production flavor');
    expect(
      reason('inputs.notes', scope, flavor: 'prod'),
      'the input notes is not set for prod',
    );
    expect(
      reason("flavor.name == 'dev'", scope),
      "flavor.name == 'dev' is false",
    );
    expect(
      reason("platform == 'ios'", const {'platform': 'android'}),
      "platform == 'ios' is false",
    );
    const shorebird = {
      'flavor': {'shorebird': true, 'prod': false},
    };
    expect(reason('!flavor.shorebird', shorebird), 'a Shorebird flavor');
    expect(reason('flavor.prod', shorebird), 'not a production flavor');
  });
}
