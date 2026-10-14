import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  const item = ReleaseNoteItem(
    sha: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
    description: 'add dark mode',
    scope: 'ui',
  );
  const notes = ReleaseNotes(
    releaseId: 'rel_1',
    version: '1.2.0',
    build: 45,
    from: 'v1.1.0+40',
    to: 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2',
    commits: 1,
    groups: [
      ReleaseNoteGroup(type: 'feat', title: 'Features', items: [item]),
    ],
    compareUrl: 'https://github.com/o/r/compare/v1.1.0+40...v1.2.0+45',
    slack: '*Features*',
    whatsapp: '*Features*',
  );

  test('a note item is not breaking unless it says so', () {
    expect(item.breaking, isFalse);
    expect(item.toJson(), {
      'sha': 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
      'description': 'add dark mode',
      'scope': 'ui',
      'breaking': false,
    });
  });

  test('the notes round-trip through JSON', () {
    expect(ReleaseNotes.fromJson(notes.toJson()), notes);
  });

  test('the notes of a first release have no from and no link', () {
    const first = ReleaseNotes(
      releaseId: 'rel_1',
      version: '1.0.0',
      build: 1,
      to: 'c3',
      commits: 0,
      groups: [],
      slack: '',
      whatsapp: '',
    );

    expect(first.toJson().containsKey('from'), isFalse);
    expect(first.toJson().containsKey('compareUrl'), isFalse);
    expect(ReleaseNotes.fromJson(first.toJson()), first);
  });
}
