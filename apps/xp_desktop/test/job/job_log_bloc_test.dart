import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/job/bloc/job_log_bloc.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';

void main() {
  late MockJobsRepository jobs;

  setUp(() => jobs = MockJobsRepository());

  JobLogBloc build() => JobLogBloc(jobs: jobs, jobId: 'job_ios');

  group('JobLogState', () {
    test('groups the lines by step and knows the last seq', () {
      expect(const JobLogState().lastSeq, 0);
      final state = JobLogState(lines: iosLog);
      expect(state.count, iosLog.length);
      expect(state.lastSeq, 220);
      expect(state.byStep.keys, [0, 1, 2]);
      expect(state.byStep[0], hasLength(2));
    });
  });

  test('events compare by value', () {
    expect(const JobLogFollowRequested().props, isEmpty);
  });

  group('JobLogBloc', () {
    blocTest<JobLogBloc, JobLogState>(
      'follows the log to its end',
      setUp: () => when(() => jobs.followLogs('job_ios')).thenAnswer(
        (_) => Stream.fromIterable([
          iosLog[0],
          const LogGapFrame(fromSeq: 2, toSeq: 2, count: 1),
          iosLog[1],
          const LogEndFrame(state: JobState.interrupted),
        ]),
      ),
      build: build,
      act: (bloc) => bloc.add(const JobLogFollowRequested()),
      verify: (bloc) {
        expect(bloc.state.lines, iosLog.take(2));
        expect(bloc.state.ended, JobState.interrupted);
        expect(bloc.state.following, isFalse);
      },
    );

    blocTest<JobLogBloc, JobLogState>(
      'follows again from the last line after a resume',
      setUp: () {
        when(() => jobs.followLogs('job_ios')).thenAnswer(
          (_) => Stream.fromIterable([
            iosLog[0],
            const LogEndFrame(state: JobState.interrupted),
          ]),
        );
        when(() => jobs.followLogs('job_ios', after: 1))
            .thenAnswer((_) => Stream.fromIterable([iosLog[1]]));
      },
      build: build,
      act: (bloc) async {
        bloc.add(const JobLogFollowRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const JobLogFollowRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.lines, iosLog.take(2));
        expect(bloc.state.ended, isNull);
        expect(bloc.state.following, isFalse);
        verify(() => jobs.followLogs('job_ios', after: 1)).called(1);
      },
    );

    blocTest<JobLogBloc, JobLogState>(
      'says why the log cannot be read',
      setUp: () => when(() => jobs.followLogs('job_ios')).thenAnswer(
        (_) =>
            Stream.error(const ApiException('No such job.', statusCode: 404)),
      ),
      build: build,
      act: (bloc) => bloc.add(const JobLogFollowRequested()),
      verify: (bloc) {
        expect(bloc.state.error, 'No such job.');
        expect(bloc.state.following, isFalse);
      },
    );

    blocTest<JobLogBloc, JobLogState>(
      'is following while lines arrive',
      setUp: () =>
          when(() => jobs.followLogs('job_ios'))
              .thenAnswer((_) => StreamController<LogFrame>().stream),
      build: build,
      act: (bloc) => bloc.add(const JobLogFollowRequested()),
      expect: () => [const JobLogState(following: true)],
    );
  });
}
