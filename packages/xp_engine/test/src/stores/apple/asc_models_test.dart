// Equality needs two separate objects, which `const` would make one.
// ignore_for_file: prefer_const_constructors

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('AscProcessingState', () {
    test('reads the values of the API', () {
      expect(AscProcessingState.fromWire('VALID'), AscProcessingState.valid);
      expect(AscProcessingState.fromWire('FAILED'), AscProcessingState.failed);
    });

    test('maps anything else to unknown', () {
      expect(AscProcessingState.fromWire('NEW'), AscProcessingState.unknown);
      expect(AscProcessingState.fromWire(null), AscProcessingState.unknown);
      expect(AscProcessingState.fromWire(''), AscProcessingState.unknown);
    });
  });

  group('ReviewSubmissionState', () {
    test('reads the values of the API', () {
      expect(
        ReviewSubmissionState.fromWire('UNRESOLVED_ISSUES'),
        ReviewSubmissionState.unresolvedIssues,
      );
    });

    test('maps anything else to unknown', () {
      expect(
        ReviewSubmissionState.fromWire('NEW'),
        ReviewSubmissionState.unknown,
      );
    });
  });

  group('PhasedReleaseState', () {
    test('reads the values of the API or none', () {
      expect(PhasedReleaseState.fromWire('PAUSED'), PhasedReleaseState.paused);
      expect(PhasedReleaseState.fromWire('SIDEWAYS'), isNull);
    });
  });

  group('AppVersionState', () {
    test('reads every value of the API', () {
      for (final state in AppVersionState.values) {
        if (state == AppVersionState.unknown) continue;
        expect(AppVersionState.fromWire(state.wire), state);
      }
    });

    test('maps anything else to unknown', () {
      expect(AppVersionState.fromWire('NEW'), AppVersionState.unknown);
      expect(AppVersionState.fromWire(null), AppVersionState.unknown);
    });

    test('knows what is live', () {
      final live = AppVersionState.values.where((s) => s.isLive);

      expect(live, {
        AppVersionState.readyForDistribution,
        AppVersionState.preorderReadyForSale,
      });
    });

    test('knows what is approved and not live: the closed trains', () {
      final closed = AppVersionState.values.where((s) => s.isApprovedNotLive);

      expect(closed, {
        AppVersionState.accepted,
        AppVersionState.pendingDeveloperRelease,
        AppVersionState.pendingAppleRelease,
        AppVersionState.pendingContract,
        AppVersionState.processingForAppStore,
      });
    });

    test('knows what is in review', () {
      final inReview = AppVersionState.values.where((s) => s.isInReview);

      expect(inReview, {
        AppVersionState.waitingForReview,
        AppVersionState.inReview,
      });
    });

    test('knows what was rejected', () {
      final rejected = AppVersionState.values.where((s) => s.isRejected);

      expect(rejected, {
        AppVersionState.rejected,
        AppVersionState.metadataRejected,
        AppVersionState.invalidBinary,
        AppVersionState.developerRejected,
      });
    });
  });

  group('AscBuildUploadState', () {
    test('reads the values of the API and knows the final ones', () {
      expect(
        AscBuildUploadState.fromWire('PROCESSING'),
        AscBuildUploadState.processing,
      );
      expect(
        AscBuildUploadState.fromWire('COMPLETE'),
        AscBuildUploadState.complete,
      );
      expect(
        [
          for (final state in AscBuildUploadState.values)
            if (state.isFinal) state,
        ],
        [AscBuildUploadState.complete, AscBuildUploadState.failed],
      );
    });

    test('maps anything else to unknown', () {
      for (final wire in ['AWAITING_UPLOAD', null, '']) {
        expect(AscBuildUploadState.fromWire(wire), AscBuildUploadState.unknown);
      }
    });
  });

  test('an upload issue reads as code: description', () {
    expect(
      '${AscUploadIssue(code: '90189', description: 'Used.')}',
      '90189: Used.',
    );
  });

  group('AscRateLimit.parse', () {
    test('reads the quota of the hour', () {
      expect(
        AscRateLimit.parse('user-hour-lim:3500;user-hour-rem:3499;'),
        const AscRateLimit(limit: 3500, remaining: 3499),
      );
    });

    test('is null without the header or without both numbers', () {
      expect(AscRateLimit.parse(null), isNull);
      expect(AscRateLimit.parse('user-hour-lim:3500;'), isNull);
      expect(AscRateLimit.parse('garbage'), isNull);
    });
  });

  test('models compare by value', () {
    expect(
      AscApp(id: '1', bundleId: 'a', name: 'A'),
      AscApp(id: '1', bundleId: 'a', name: 'A'),
    );
    expect(
      AscUploadIssue(code: '1', description: 'd'),
      AscUploadIssue(code: '1', description: 'd'),
    );
    expect(
      AscBuildUpload(
        id: 'u',
        state: AscBuildUploadState.failed,
        errors: const [AscUploadIssue(code: '1', description: 'd')],
        buildId: 'b',
      ),
      AscBuildUpload(
        id: 'u',
        state: AscBuildUploadState.failed,
        errors: const [AscUploadIssue(code: '1', description: 'd')],
        buildId: 'b',
      ),
    );
    expect(
      AscBuild(
        id: 'b',
        buildNumber: '45',
        processingState: AscProcessingState.valid,
      ),
      AscBuild(
        id: 'b',
        buildNumber: '45',
        processingState: AscProcessingState.valid,
      ),
    );
    expect(
      AscAppStoreVersion(
        id: 'v',
        versionString: '1.0.0',
        platform: 'IOS',
        state: AppVersionState.inReview,
      ),
      AscAppStoreVersion(
        id: 'v',
        versionString: '1.0.0',
        platform: 'IOS',
        state: AppVersionState.inReview,
      ),
    );
    expect(
      AscReviewSubmission(
        id: 's',
        state: ReviewSubmissionState.complete,
        platform: 'IOS',
      ),
      AscReviewSubmission(
        id: 's',
        state: ReviewSubmissionState.complete,
        platform: 'IOS',
      ),
    );
    expect(
      AscPhasedRelease(id: 'p', state: PhasedReleaseState.active),
      AscPhasedRelease(id: 'p', state: PhasedReleaseState.active),
    );
  });
}
