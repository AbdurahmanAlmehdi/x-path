import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const builder = ReleaseNotesBuilder();

  GitCommit commit(String subject, {String body = '', String sha = 'a'}) =>
      GitCommit(sha: sha * 40, subject: subject, body: body);

  ReleaseNotes notes(
    List<GitCommit> commits, {
    String? from = 'v1.1.0+40',
    String? compareUrl = 'https://github.com/octo/demo/compare/v1.1.0%2B40...b',
  }) => builder.build(
    releaseId: 'rel_1',
    title: 'octo/demo prod 1.2.0 (45)',
    version: '1.2.0',
    build: 45,
    to: 'b' * 40,
    commits: commits,
    from: from,
    compareUrl: compareUrl,
  );

  test('groups the commits by type, in the order of the notes', () {
    final result = notes([
      commit('fix(login): stop the spinner', sha: '1'),
      commit('docs: explain the flavors', sha: '2'),
      commit('feat(ui): add dark mode', sha: '3'),
      commit('perf: cache the catalogue', sha: '4'),
      commit('refactor!: drop the old API', sha: '5'),
      commit('chore: bump the SDK', sha: '6'),
      commit('Fix typo', sha: '7'),
      commit('feat: add search', sha: '8'),
    ]);

    expect(result.groups.map((group) => group.type), [
      'breaking',
      'feat',
      'fix',
      'perf',
      'docs',
      'other',
    ]);
    expect(result.commits, 8);
    expect(
      result.groups
          .firstWhere((g) => g.type == 'feat')
          .items
          .map((item) => (item.scope, item.description)),
      [('ui', 'add dark mode'), (null, 'add search')],
    );
    expect(
      result.groups
          .firstWhere((g) => g.type == 'other')
          .items
          .map((item) => item.description),
      ['bump the SDK', 'Fix typo'],
    );
  });

  test('a breaking commit is listed once, under breaking changes', () {
    final result = notes([
      commit('feat(api)!: rename the field', sha: '1'),
      commit(
        'fix: tidy',
        body: 'Details.\n\nBREAKING CHANGE: it is gone',
        sha: '2',
      ),
      commit('fix: a plain fix', body: 'BREAKING-CHANGE-ish words', sha: '3'),
    ]);

    final breaking = result.groups.first;
    expect(breaking.type, 'breaking');
    expect(breaking.title, 'Breaking changes');
    expect(breaking.items.map((item) => item.description), [
      'rename the field',
      'tidy',
    ]);
    expect(breaking.items.every((item) => item.breaking), isTrue);
    expect(result.groups.last.type, 'fix');
    expect(result.groups.last.items.single.breaking, isFalse);
  });

  test('leaves out the version commits XPath makes', () {
    final result = notes([
      commit('chore(release): 1.2.0+45', sha: '1'),
      commit('chore(deps): bump http', sha: '2'),
    ]);

    expect(result.commits, 1);
    expect(result.groups.single.items.single.description, 'bump http');
  });

  test('reads the type whatever the case and the spacing of the scope', () {
    final result = notes([commit('FEAT( ui ): shout', sha: '1')]);

    expect(result.groups.single.type, 'feat');
    expect(result.groups.single.items.single.scope, 'ui');
  });

  test('an empty scope is no scope', () {
    final result = notes([commit('feat(): bare', sha: '1')]);

    expect(result.groups.single.items.single.scope, isNull);
  });

  group('the Slack text', () {
    test('has bold headings, bullets and a link', () {
      final result = notes([
        commit('feat(ui): add dark mode', sha: '1'),
        commit('fix: handle <b> & more', sha: '2'),
      ]);

      expect(
        result.slack,
        '*octo/demo prod 1.2.0 (45)*\n'
        'Changes since v1.1.0+40.\n'
        '\n'
        '*Features*\n'
        '• ui: add dark mode\n'
        '\n'
        '*Fixes*\n'
        '• handle &lt;b&gt; &amp; more\n'
        '\n'
        '<https://github.com/octo/demo/compare/v1.1.0%2B40...b|Full changelog>',
      );
    });
  });

  group('the WhatsApp text', () {
    test('has bold headings and bullets and no link markup', () {
      final result = notes([
        commit('feat(ui): add dark mode', sha: '1'),
        commit('fix: handle <b> & more', sha: '2'),
      ]);

      expect(
        result.whatsapp,
        '*octo/demo prod 1.2.0 (45)*\n'
        'Changes since v1.1.0+40.\n'
        '\n'
        '*Features*\n'
        '• ui: add dark mode\n'
        '\n'
        '*Fixes*\n'
        '• handle <b> & more\n'
        '\n'
        'Full changelog: https://github.com/octo/demo/compare/v1.1.0%2B40...b',
      );
      expect(result.whatsapp, isNot(contains('<https')));
    });
  });

  group('with nothing to list', () {
    test('after a release before says nothing changed', () {
      final result = notes(const [], compareUrl: null);

      expect(result.groups, isEmpty);
      expect(result.commits, 0);
      expect(
        result.slack,
        '*octo/demo prod 1.2.0 (45)*\nNo changes since v1.1.0+40.',
      );
      expect(result.compareUrl, isNull);
    });

    test('on a first release says there are no commits', () {
      final result = notes(const [], from: null, compareUrl: null);

      expect(result.whatsapp, '*octo/demo prod 1.2.0 (45)*\nNo commits.');
    });

    test('a first release with commits has no "since" line', () {
      final result = notes(
        [commit('feat: first', sha: '1')],
        from: null,
        compareUrl: null,
      );

      expect(result.from, isNull);
      expect(result.slack, isNot(contains('Changes since')));
      expect(result.slack, contains('• first'));
    });
  });

  test('carries what the endpoint needs to say about the release', () {
    final result = notes([commit('fix: x', sha: '1')]);

    expect(result.releaseId, 'rel_1');
    expect(result.version, '1.2.0');
    expect(result.build, 45);
    expect(result.from, 'v1.1.0+40');
    expect(result.to, 'b' * 40);
    expect(result.groups.single, isA<ReleaseNoteGroup>());
  });
}
