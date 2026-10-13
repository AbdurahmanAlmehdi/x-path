import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('GitException prints its message', () {
    const error = GitException('boom');

    expect(error.message, 'boom');
    expect(error.toString(), 'GitException: boom');
  });

  test('GitRefNotFoundException names the ref', () {
    const error = GitRefNotFoundException('main');

    expect(error, isA<GitException>());
    expect(error.ref, 'main');
    expect(error.toString(), 'GitRefNotFoundException: Cannot find main.');
  });

  test('GitTagConflictException names the tag and both commits', () {
    const error = GitTagConflictException(
      tag: 'v1.0.0+1',
      existingSha: 'aaa',
      requestedSha: 'bbb',
    );

    expect(error, isA<GitException>());
    expect(error.tag, 'v1.0.0+1');
    expect(error.existingSha, 'aaa');
    expect(error.requestedSha, 'bbb');
    expect(
      error.toString(),
      'GitTagConflictException: Tag v1.0.0+1 is on aaa, not on bbb.',
    );
  });

  test('GitBranchConflictException names the branch and both commits', () {
    const error = GitBranchConflictException(
      branch: 'release/1.0',
      currentSha: 'aaa',
      requestedSha: 'bbb',
    );

    expect(error, isA<GitException>());
    expect(error.branch, 'release/1.0');
    expect(error.currentSha, 'aaa');
    expect(error.requestedSha, 'bbb');
    expect(error.toString(), contains('release/1.0 is on aaa'));
  });

  test('GitPushRejectedException prints its message', () {
    const error = GitPushRejectedException('non-fast-forward');

    expect(error, isA<GitException>());
    expect(error.toString(), 'GitPushRejectedException: non-fast-forward');
  });
}
