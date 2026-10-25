import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  const plan = DispatchPlan(
    flavors: ['dev'],
    platforms: ['android', 'ios'],
    currentVersion: '1.2.3+45',
    version: '1.2.3',
    build: 46,
    releaseVersion: '1.2.0+30',
    stages: [
      PlannedStage(
        name: 'build',
        jobs: [
          PlannedJob(
            name: 'Build dev for android',
            flavor: 'dev',
            platform: 'android',
            capabilities: ['android', 'flutter'],
            engineOnly: false,
            local: true,
            runner: 'linux-builder-01',
          ),
          PlannedJob(
            name: 'Build dev for ios',
            capabilities: ['ios-sign'],
            engineOnly: false,
            local: false,
            waitReason: 'No runner can do ios-sign.',
          ),
        ],
      ),
      PlannedStage(
        name: 'upload',
        gates: ['store_submission', 'push'],
        jobs: [PlannedJob(name: 'Upload', engineOnly: true, local: true)],
      ),
    ],
    skipped: [
      SkippedJob(
        name: 'Upload dev for ios',
        stage: 'upload',
        flavor: 'dev',
        platform: 'ios',
        reason: 'no App Store app id for dev',
      ),
    ],
  );

  test('round-trips through JSON', () {
    expect(DispatchPlan.fromJson(plan.toJson()), plan);
    expect(
      DispatchPlan.fromJson(const {
        'flavors': <String>[],
        'platforms': <String>[],
      }),
      const DispatchPlan(flavors: [], platforms: []),
    );
  });

  test('counts its jobs and gates, and says whether it is blocked', () {
    expect(plan.jobCount, 3);
    expect(plan.gates, ['store_submission', 'push']);
    expect(plan.blocked, isFalse);
    expect(
      const DispatchPlan(
        flavors: [],
        platforms: [],
        skipped: [SkippedJob(name: 'x', stage: 's', reason: 'r', blocks: true)],
      ).blocked,
      isTrue,
    );
  });
}
