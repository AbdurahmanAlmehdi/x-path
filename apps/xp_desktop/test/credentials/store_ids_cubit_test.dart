import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/credentials.dart';

import '../helpers/fakes.dart';

void main() {
  setUpAll(() => registerFallbackValue(const ProfileEdits()));

  late MockProjectsRepository projects;

  setUp(() => projects = MockProjectsRepository());

  StoreIdsCubit build() =>
      StoreIdsCubit(projects: projects, projectId: 'prj_1');

  Future<void> save(StoreIdsCubit cubit) => cubit.save(
    app: '.',
    flavor: 'dev',
    firebaseAndroid: ' 1:1:android:a ',
    firebaseIos: '',
    appleAppId: '123',
  );

  blocTest<StoreIdsCubit, StoreIdsState>(
    'saves the ids as an edit of the flavor, an empty one removing it',
    setUp: () =>
        when(() => projects.editProject('prj_1', any()))
            .thenAnswer((_) async => mataa),
    build: build,
    act: save,
    expect: () => const [
      StoreIdsState(status: StoreIdsStatus.saving),
      StoreIdsState(status: StoreIdsStatus.saved),
    ],
    verify: (_) {
      final edits =
          verify(() => projects.editProject('prj_1', captureAny()))
                  .captured
                  .single
              as ProfileEdits;
      expect(
        edits,
        const ProfileEdits(
          apps: [
            AppEdit(
              path: '.',
              flavors: [
                FlavorEdit(
                  name: 'dev',
                  firebaseAppId: {'android': '1:1:android:a', 'ios': ''},
                  appleAppId: '123',
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  blocTest<StoreIdsCubit, StoreIdsState>(
    'says why the engine refused',
    setUp: () => when(
      () => projects.editProject('prj_1', any()),
    ).thenThrow(const ApiException('Not a Firebase app id.', statusCode: 400)),
    build: build,
    act: save,
    expect: () => const [
      StoreIdsState(status: StoreIdsStatus.saving),
      StoreIdsState(
        status: StoreIdsStatus.failed,
        error: 'Not a Firebase app id.',
      ),
    ],
  );
}
