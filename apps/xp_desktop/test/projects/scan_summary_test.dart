import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/projects/widgets/scan_summary.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Project _withFindings(List<Finding> findings) => Project(
  id: mataa.id,
  githubRepoId: mataa.githubRepoId,
  fullName: mataa.fullName,
  remote: mataa.remote,
  defaultBaseBranch: mataa.defaultBaseBranch,
  profile: mataa.profile,
  findings: findings,
);

const _missing = Finding(
  severity: FindingSeverity.info,
  code: 'firebase_app_id_missing',
  message: 'The Firebase files name no ios app for flavor dev.',
  fix: 'Set the Firebase app id of flavor dev in XPath.',
  app: '.',
  flavor: 'dev',
);

void main() {
  testWidgets('a missing Firebase id opens the store ids of its flavor', (
    tester,
  ) async {
    final projects = MockProjectsRepository();
    when(() => projects.watchCredentials(any()))
        .thenAnswer((_) => Stream.value(const Snapshot([])));
    await tester.pumpApp(
      SingleChildScrollView(
        child: ScanSummary(_withFindings(const [_missing])),
      ),
      projectsRepository: projects,
    );

    await tester.tap(find.text('Set the id…'));
    await tester.pumpAndSettle();

    expect(find.byType(FlavorCredentialsSheet), findsOneWidget);
    expect(find.text('Credentials of dev'), findsOneWidget);
    expect(find.byKey(const Key('flavorCredentials.storeIds')), findsOneWidget);
  });

  testWidgets('other findings, and one of an app that is gone, link nowhere', (
    tester,
  ) async {
    await tester.pumpApp(
      SingleChildScrollView(
        child: ScanSummary(
          _withFindings(const [
            Finding(
              severity: FindingSeverity.warning,
              code: 'fvmrc_missing',
              message: 'No .fvmrc.',
              fix: 'Add one.',
            ),
            Finding(
              severity: FindingSeverity.info,
              code: 'firebase_app_id_missing',
              message: 'Gone.',
              fix: 'x',
              app: 'apps/gone',
            ),
          ]),
        ),
      ),
    );

    expect(find.text('Set the id…'), findsNothing);
  });
}
