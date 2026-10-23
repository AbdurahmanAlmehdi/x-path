import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final project = Project(
    id: 'prj_1',
    host: 'github.com',
    sourceKey: '42',
    githubRepoId: 42,
    fullName: 'octo/app',
    remote: 'https://github.com/octo/app.git',
    localPath: '/work/app',
    defaultBaseBranch: 'dev',
    profile: const ProjectProfile(
      apps: [AppProfile(name: 'a', path: '.')],
    ),
    findings: const [
      Finding(
        severity: FindingSeverity.info,
        code: 'c',
        message: 'm',
        fix: 'f',
      ),
    ],
    scannedAt: DateTime.utc(2026, 10, 13, 9),
  );

  group('Project', () {
    test('round-trips through JSON', () {
      expect(Project.fromJson(project.toJson()), project);
    });

    test('writes the scan time in UTC', () {
      expect(project.toJson()['scannedAt'], '2026-10-13T09:00:00.000Z');
    });

    test('reads a project of an engine older than ADR 0015 as GitHub', () {
      final read = Project.fromJson(const {
        'id': 'prj_2',
        'githubRepoId': 12,
        'fullName': 'o/r',
        'remote': 'https://github.com/o/r.git',
        'defaultBaseBranch': 'main',
      });

      expect(read.host, Project.githubHost);
      expect(read.sourceKey, '12');
      expect(read.isOnGitHub, isTrue);
    });

    test('reads a project that is not on GitHub', () {
      const bitbucket = Project(
        id: 'prj_3',
        host: 'bitbucket.org',
        sourceKey: 'h0123456789abcdef',
        fullName: 'ws/group/repo',
        remote: 'git@bitbucket.org:ws/group/repo.git',
        defaultBaseBranch: 'main',
      );

      expect(Project.fromJson(bitbucket.toJson()), bitbucket);
      expect(bitbucket.toJson().containsKey('githubRepoId'), isFalse);
      expect(bitbucket.isOnGitHub, isFalse);
    });

    test('leaves out what is unknown and defaults the rest', () {
      final read = Project.fromJson(const {
        'id': 'prj_2',
        'host': 'github.com',
        'sourceKey': '1',
        'githubRepoId': 1,
        'fullName': 'o/r',
        'remote': 'https://github.com/o/r.git',
        'defaultBaseBranch': 'main',
      });

      expect(read.profile, const ProjectProfile());
      expect(read.findings, isEmpty);
      expect(read.toJson().containsKey('localPath'), isFalse);
      expect(read.toJson().containsKey('scannedAt'), isFalse);
    });
  });

  test('ProjectsResponse round-trips through JSON', () {
    final response = ProjectsResponse([project]);

    expect(ProjectsResponse.fromJson(response.toJson()), response);
  });

  test('AddProjectRequest round-trips through JSON', () {
    const byPath = AddProjectRequest(path: '/work/app');
    const byRemote = AddProjectRequest(remote: 'octo/app');

    expect(AddProjectRequest.fromJson(byPath.toJson()), byPath);
    expect(byPath.toJson(), {'path': '/work/app'});
    expect(AddProjectRequest.fromJson(byRemote.toJson()), byRemote);
  });

  test('AddProjectRequest names a field of the wrong type', () {
    expect(
      () => AddProjectRequest.fromJson(const {'path': 3}),
      throwsA(isA<CheckedFromJsonException>()),
    );
  });
}
