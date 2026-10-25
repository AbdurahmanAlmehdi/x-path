import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/projects.dart';

import '../helpers/fakes.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('names the git host of a project, or a local repository', () {
    expect(mataa.hostLabel(l10n), 'github.com');
    expect(shop.hostLabel(l10n), 'bitbucket.org');
    expect(
      const Project(
        id: 'prj_4',
        host: 'local',
        sourceKey: 'h0123456789abcdef',
        fullName: 'srv/git/app',
        remote: 'file:///srv/git/app.git',
        defaultBaseBranch: 'main',
      ).hostLabel(l10n),
      'local repository',
    );
  });
}
