import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/git/git_models.dart';

/// Turns the commits of a release into notes: groups by conventional-commit
/// type, as Slack `mrkdwn` and as WhatsApp text (D-22).
class ReleaseNotesBuilder {
  /// Creates a builder.
  const new();

  /// The groups, in the order the notes list them, with the type each one
  /// takes. Types the table does not know (`chore`, `ci`, `build`, `test`,
  /// `style`, `revert`, and any message that is not a conventional commit)
  /// are `other`.
  static const _groups = [
    ('breaking', 'Breaking changes'),
    ('feat', 'Features'),
    ('fix', 'Fixes'),
    ('perf', 'Performance'),
    ('refactor', 'Refactoring'),
    ('docs', 'Documentation'),
    ('other', 'Other changes'),
  ];

  static final _subject = RegExp(
    r'^(?<type>[A-Za-z]+)(?:\((?<scope>[^()]*)\))?(?<bang>!)?:'
    r'\s+(?<text>\S.*)$',
  );
  static final _breakingFooter = RegExp(
    '^BREAKING[ -]CHANGE:',
    multiLine: true,
  );

  /// The notes of the release [releaseId] at [version] and [build], made of
  /// [commits] (newest first) that end at [to].
  ///
  /// [title] heads the text, [from] is the tag of the release before and
  /// [compareUrl] the link to the comparison on GitHub, when there are any.
  ReleaseNotes build({
    required String releaseId,
    required String title,
    required String version,
    required int build,
    required String to,
    required List<GitCommit> commits,
    String? from,
    String? compareUrl,
  }) {
    final byType = <String, List<ReleaseNoteItem>>{};
    var counted = 0;
    for (final commit in commits) {
      final parsed = _parse(commit);
      // XPath's own version commits say nothing to a reader.
      if (parsed == null) continue;
      counted++;
      byType.putIfAbsent(parsed.$1, () => []).add(parsed.$2);
    }
    final groups = [
      for (final (type, heading) in _groups)
        if (byType[type] case final items?)
          ReleaseNoteGroup(type: type, title: heading, items: items),
    ];
    String render({
      required String Function(String) bold,
      required String Function(String) text,
      required String Function(String) link,
    }) {
      final lines = [
        bold(title),
        if (groups.isEmpty && from == null)
          'No commits.'
        else if (groups.isEmpty)
          'No changes since $from.'
        else if (from != null)
          'Changes since $from.',
        for (final group in groups) ...[
          '',
          bold(group.title),
          for (final item in group.items) '\u2022 ${text(_describe(item))}',
        ],
        if (compareUrl != null) ...['', link(compareUrl)],
      ];
      return lines.join('\n');
    }

    return ReleaseNotes(
      releaseId: releaseId,
      version: version,
      build: build,
      from: from,
      to: to,
      commits: counted,
      groups: groups,
      compareUrl: compareUrl,
      slack: render(
        bold: (value) => '*${_slack(value)}*',
        text: _slack,
        link: (url) => '<$url|Full changelog>',
      ),
      whatsapp: render(
        bold: (value) => '*$value*',
        text: (value) => value,
        link: (url) => 'Full changelog: $url',
      ),
    );
  }

  /// The type and item of [commit], or `null` for a commit to leave out.
  (String, ReleaseNoteItem)? _parse(GitCommit commit) {
    final match = _subject.firstMatch(commit.subject);
    if (match == null) {
      return (
        'other',
        ReleaseNoteItem(sha: commit.sha, description: commit.subject.trim()),
      );
    }
    final type = match.namedGroup('type')!.toLowerCase();
    final scope = match.namedGroup('scope')?.trim();
    if (type == 'chore' && scope == 'release') return null;
    final breaking =
        match.namedGroup('bang') != null ||
        _breakingFooter.hasMatch(commit.body);
    final item = ReleaseNoteItem(
      sha: commit.sha,
      description: match.namedGroup('text')!.trim(),
      scope: scope == null || scope.isEmpty ? null : scope,
      breaking: breaking,
    );
    final group = breaking
        ? 'breaking'
        : const {'feat', 'fix', 'perf', 'refactor', 'docs'}.contains(type)
        ? type
        : 'other';
    return (group, item);
  }

  static String _describe(ReleaseNoteItem item) => item.scope == null
      ? item.description
      : '${item.scope}: ${item.description}';

  static String _slack(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
