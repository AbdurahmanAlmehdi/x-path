import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const host = {
    'PATH': '/usr/bin',
    'HOME': '/home/me',
    'LANG': 'en_US.UTF-8',
    'LC_ALL': 'C',
    'LC_CTYPE': 'UTF-8',
    'TMPDIR': '/tmp',
    'USER': 'me',
    'SHELL': '/bin/zsh',
    'GITHUB_TOKEN': 'ghp_secret',
    'AWS_SECRET_ACCESS_KEY': 'secret',
    'ANDROID_HOME': '/sdk',
  };

  test('keeps only the allowed variables of the host', () {
    expect(allowlistedEnvironment(host), {
      'PATH': '/usr/bin',
      'HOME': '/home/me',
      'LANG': 'en_US.UTF-8',
      'LC_ALL': 'C',
      'LC_CTYPE': 'UTF-8',
      'TMPDIR': '/tmp',
      'USER': 'me',
      'SHELL': '/bin/zsh',
    });
  });

  test('adds the variables the step asks for from the host', () {
    final environment = allowlistedEnvironment(
      host,
      passThrough: ['ANDROID_HOME', 'NOT_SET'],
    );

    expect(environment['ANDROID_HOME'], '/sdk');
    expect(environment, isNot(contains('NOT_SET')));
    expect(environment, isNot(contains('GITHUB_TOKEN')));
  });

  test('lets the values a step declares win', () {
    final environment = allowlistedEnvironment(
      host,
      passThrough: ['ANDROID_HOME'],
      values: {'HOME': '/work', 'ANDROID_HOME': '/other', 'CI': 'true'},
    );

    expect(environment['HOME'], '/work');
    expect(environment['ANDROID_HOME'], '/other');
    expect(environment['CI'], 'true');
  });

  test('is empty for an empty host', () {
    expect(allowlistedEnvironment(const {}), isEmpty);
  });
}
