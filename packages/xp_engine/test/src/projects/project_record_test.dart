import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  ProjectRecord record({ProfileEdits edits = const ProfileEdits()}) =>
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '7',
        githubRepoId: 7,
        fullName: 'octo/app',
        remote: 'https://github.com/octo/app.git',
        githubDefaultBranch: 'main',
        localPath: '/work/app',
        scan: const ProjectProfile(
          apps: [
            AppProfile(
              name: 'app',
              path: '.',
              flavors: [
                FlavorProfile(name: 'dev', entrypoint: 'lib/main.dart'),
              ],
            ),
          ],
        ),
        findings: const [
          Finding(
            severity: FindingSeverity.info,
            code: 'c',
            message: 'm',
            fix: 'f',
          ),
        ],
        scannedAt: DateTime.utc(2026, 10, 13),
        edits: edits,
      );

  test('the base branch is GitHub default unless the owner edited it', () {
    expect(record().defaultBaseBranch, 'main');
    expect(
      record(edits: const ProfileEdits(defaultBaseBranch: 'dev'))
          .defaultBaseBranch,
      'dev',
    );
  });

  test('the profile is the scan with the edits applied', () {
    final edited = record(
      edits: const ProfileEdits(
        apps: [AppEdit(path: '.', storeCountry: 'ly')],
      ),
    );

    expect(record().profile, record().scan);
    expect(edited.profile.apps.single.storeCountry, 'ly');
    expect(edited.scan.apps.single.storeCountry, 'us');
  });

  test('toProject shows the effective profile and the scan details', () {
    final project = record(edits: const ProfileEdits(defaultBaseBranch: 'dev'))
        .toProject();

    expect(project.id, 'prj_1');
    expect(project.host, 'github.com');
    expect(project.sourceKey, '7');
    expect(project.githubRepoId, 7);
    expect(project.fullName, 'octo/app');
    expect(project.remote, 'https://github.com/octo/app.git');
    expect(project.localPath, '/work/app');
    expect(project.defaultBaseBranch, 'dev');
    expect(project.findings, record().findings);
    expect(project.scannedAt, DateTime.utc(2026, 10, 13));
  });

  test('copyWith replaces only what is given', () {
    final changed = record().copyWith(
      fullName: 'octo/renamed',
      remote: 'https://github.com/octo/renamed.git',
      githubDefaultBranch: 'dev',
      scan: const ProjectProfile(),
      findings: const [],
      scannedAt: DateTime.utc(2027),
      edits: const ProfileEdits(defaultBaseBranch: 'x'),
    );

    expect(record().copyWith(), record());
    expect(changed.fullName, 'octo/renamed');
    expect(changed.remote, 'https://github.com/octo/renamed.git');
    expect(changed.githubDefaultBranch, 'dev');
    expect(changed.scan, const ProjectProfile());
    expect(changed.findings, isEmpty);
    expect(changed.scannedAt, DateTime.utc(2027));
    expect(changed.edits.defaultBaseBranch, 'x');
    expect(changed.id, 'prj_1');
    expect(changed.host, 'github.com');
    expect(changed.sourceKey, '7');
    expect(changed.githubRepoId, 7);
    expect(changed.localPath, '/work/app');
  });

  test('has a GitHub repository id exactly when it is on GitHub', () {
    ProjectRecord on(String host, int? githubRepoId) => ProjectRecord(
      id: 'prj_x',
      host: host,
      sourceKey: 'h0123456789abcdef',
      githubRepoId: githubRepoId,
      fullName: 'o/r',
      remote: 'r',
      githubDefaultBranch: 'main',
      scan: const ProjectProfile(),
      findings: const [],
      scannedAt: DateTime.utc(2026),
    );

    expect(() => on('github.com', null), throwsA(isA<AssertionError>()));
    expect(() => on('bitbucket.org', 7), throwsA(isA<AssertionError>()));
    expect(on('bitbucket.org', null).githubRepoId, isNull);
  });

  test('only a project on github.com is on GitHub', () {
    expect(record().isOnGitHub, isTrue);
    final local = ProjectRecord(
      id: 'prj_2',
      host: 'local',
      sourceKey: 'h0123456789abcdef',
      fullName: 'srv/git/app',
      remote: 'file:///srv/git/app.git',
      githubDefaultBranch: 'main',
      scan: const ProjectProfile(),
      findings: const [],
      scannedAt: DateTime.utc(2026),
    );
    expect(local.isOnGitHub, isFalse);
    expect(local.toProject().isOnGitHub, isFalse);
    expect(local.toProject().githubRepoId, isNull);
  });
}
