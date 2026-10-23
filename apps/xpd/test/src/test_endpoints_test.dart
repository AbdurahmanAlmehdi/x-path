import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  test('a real engine has none of them', () {
    final endpoints = TestEndpoints.fromEnvironment({'PATH': '/usr/bin'});

    expect(endpoints.githubApiUrl, isNull);
    expect(endpoints.firebaseUrl, isNull);
    expect(endpoints.ascUrl, isNull);
    expect(endpoints.playUrl, isNull);
    expect(endpoints.fileSecrets, isFalse);
    expect(endpoints.leaseSeconds, isNull);
    expect(endpoints.ascUploadSeconds, isNull);
    expect(endpoints.isActive, isFalse);
    expect(endpoints.secretStoreSystem('macos'), 'macos');
  });

  test('reads the addresses of the fakes and the secrets setting', () {
    final endpoints = TestEndpoints.fromEnvironment({
      TestEndpoints.githubApiVariable: 'http://127.0.0.1:1234',
      TestEndpoints.firebaseVariable: 'http://localhost:5678',
      TestEndpoints.ascVariable: 'http://127.0.0.1:2468',
      TestEndpoints.playVariable: 'http://localhost:1357',
      TestEndpoints.fileSecretsVariable: '1',
    });

    expect(endpoints.githubApiUrl, Uri.parse('http://127.0.0.1:1234'));
    expect(endpoints.firebaseUrl, Uri.parse('http://localhost:5678'));
    expect(endpoints.ascUrl, Uri.parse('http://127.0.0.1:2468'));
    expect(endpoints.playUrl, Uri.parse('http://localhost:1357'));
    expect(endpoints.fileSecrets, isTrue);
    expect(endpoints.isActive, isTrue);
    expect(endpoints.secretStoreSystem('macos'), 'linux');
  });

  test('any one of them makes the engine a test engine', () {
    for (final environment in [
      {TestEndpoints.githubApiVariable: 'http://x'},
      {TestEndpoints.firebaseVariable: 'http://x'},
      {TestEndpoints.ascVariable: 'http://x'},
      {TestEndpoints.playVariable: 'http://x'},
      {TestEndpoints.fileSecretsVariable: '1'},
      {TestEndpoints.leaseSecondsVariable: '6'},
      {TestEndpoints.ascUploadSecondsVariable: '5'},
    ]) {
      expect(TestEndpoints.fromEnvironment(environment).isActive, isTrue);
    }
  });

  test('reads a shorter lease', () {
    expect(
      TestEndpoints.fromEnvironment({TestEndpoints.leaseSecondsVariable: '6'})
          .leaseSeconds,
      6,
    );
  });

  test('reads a shorter wait for a build upload', () {
    expect(
      TestEndpoints.fromEnvironment({
        TestEndpoints.ascUploadSecondsVariable: '5',
      }).ascUploadSeconds,
      5,
    );
  });

  test('an empty address or another value is none', () {
    final endpoints = TestEndpoints.fromEnvironment({
      TestEndpoints.githubApiVariable: '',
      TestEndpoints.fileSecretsVariable: 'yes',
      TestEndpoints.leaseSecondsVariable: 'soon',
    });

    expect(endpoints.isActive, isFalse);
  });
}
