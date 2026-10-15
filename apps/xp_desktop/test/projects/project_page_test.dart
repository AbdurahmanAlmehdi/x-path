import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/projects/projects.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => registerFallbackValue(const ProjectsSubscriptionRequested()));

  group('ProjectPage', () {
    testWidgets('shows the scan: apps, flavors and findings', (tester) async {
      await tester.pumpApp(
        const ProjectPage('prj_1'),
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa]),
        ),
      );
      expect(find.text('acme/mataa_new_app'), findsOneWidget);
      expect(find.text('main · 1 app'), findsOneWidget);
      expect(find.text('Mataa customer app'), findsOneWidget);
      expect(
        find.text('path . · Flutter 3.47.6 · store country LY'),
        findsOneWidget,
      );
      expect(find.text('com.sixdtec.mata'), findsOneWidget);
      expect(find.text('com.mataaa.dev'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'dev has no Android ID');
      expect(find.text('on'), findsOneWidget);
      expect(find.text('off'), findsOneWidget);
      expect(find.text('prod'), findsNWidgets(2), reason: 'flavor and tag');
      // Worst first.
      final warning = tester.getTopLeft(
        find.text('iOS dev bundle ID differs from Android'),
      );
      final info = tester.getTopLeft(
        find.text('Shorebird enabled for prod only'),
      );
      expect(warning.dy, lessThan(info.dy));
      expect(find.text('Fix: Use the same ID on both.'), findsOneWidget);
      expect(find.text('ios/Runner.xcodeproj/project.pbxproj'), findsOneWidget);
    });

    testWidgets('scans again', (tester) async {
      final projects = projectsIn(
        const ProjectsState(loaded: true, projects: [mataa], error: 'Boom'),
      );
      await tester.pumpApp(const ProjectPage('prj_1'), projects: projects);
      expect(find.text('Boom'), findsOneWidget);
      await tester.tap(find.text('Scan again'));
      verify(() => projects.add(const ProjectScanRequested('prj_1'))).called(1);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      final projects = projectsIn(
        const ProjectsState(loaded: true, projects: [captain]),
      );
      await tester.pumpApp(
        const ProjectPage('prj_2'),
        projects: projects,
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
      );
      await tester.tap(find.text('Scan again'));
      verifyNever(() => projects.add(any()));
      expect(find.text('No App Store Connect API key'), findsOneWidget);
    });

    testWidgets('says when the project is gone', (tester) async {
      await tester.pumpApp(const ProjectPage('prj_9'));
      expect(
        find.text('This project is no longer on the engine.'),
        findsOneWidget,
      );
    });

    testWidgets('says when the scan found nothing', (tester) async {
      await tester.pumpApp(
        const ProjectPage('prj_3'),
        projects: projectsIn(
          const ProjectsState(
            loaded: true,
            projects: [
              Project(
                id: 'prj_3',
                githubRepoId: 3,
                fullName: 'acme/empty',
                remote: 'r',
                defaultBaseBranch: 'main',
              ),
            ],
          ),
        ),
      );
      expect(find.text('No Flutter app found.'), findsOneWidget);
      expect(find.text('Nothing to fix.'), findsOneWidget);
    });
  });
}
