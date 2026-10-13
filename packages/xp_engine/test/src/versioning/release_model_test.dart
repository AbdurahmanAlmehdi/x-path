import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const model = ReleaseModel();
  final version = VersionName.parse('5.4.1');

  group('defaults', () {
    test('are the release model of docs/RELEASING.md', () {
      expect(model.branchName(version), 'release/5.4.1');
      expect(model.tagName(version, 3283), 'v5.4.1+3283');
      expect(model.patchTagName(version, 3283, 2), 'v5.4.1+3283-p2');
      expect(model.problems, isEmpty);
    });

    test('round-trip through JSON', () {
      expect(ReleaseModel.fromJson(model.toJson()), model);
      expect(ReleaseModel.fromJson(const {}), model);
    });
  });

  group('patterns that name the app and flavor', () {
    const oneavant = ReleaseModel(
      branchPattern: 'release/{app}/{version}',
      tagPattern: '{app}/{flavor}/v{version}+{build}',
      patchTagPattern: '{app}/{flavor}/v{version}+{build}-p{n}',
    );
    const scope = TagScope(app: 'mobile', flavor: 'prod');

    test('fill the names in', () {
      expect(
        oneavant.tagName(version, 7, scope: scope),
        'mobile/prod/v5.4.1+7',
      );
      expect(
        oneavant.patchTagName(version, 7, 1, scope: scope),
        'mobile/prod/v5.4.1+7-p1',
      );
      expect(
        oneavant.branchName(version, scope: scope),
        'release/mobile/5.4.1',
      );
    });

    test('need a value for each name', () {
      expect(() => oneavant.tagName(version, 7), throwsArgumentError);
      expect(
        () => oneavant.tagName(version, 7, scope: const TagScope(app: 'm')),
        throwsArgumentError,
      );
    });

    test('are read back only for their own app and flavor', () {
      expect(
        oneavant.parseTag('mobile/prod/v5.4.1+7', scope: scope),
        const ReleaseTag(
          name: 'mobile/prod/v5.4.1+7',
          version: VersionName(5, 4, 1),
          build: 7,
        ),
      );
      expect(oneavant.parseTag('mobile/dev/v5.4.1+7', scope: scope), isNull);
      expect(oneavant.parseTag('web/prod/v5.4.1+7', scope: scope), isNull);
      // Without a scope any app and flavor matches.
      expect(oneavant.parseTag('web/dev/v1.0.0+2')?.build, 2);
      expect(
        oneavant
            .parseTag(
              'mobile/dev/v1.0.0+2',
              scope: const TagScope(app: 'mobile'),
            )
            ?.build,
        2,
      );
      expect(
        oneavant.parseTag(
          'web/dev/v1.0.0+2',
          scope: const TagScope(app: 'mobile'),
        ),
        isNull,
      );
    });
  });

  group('parseTag', () {
    test('reads a store tag and a patch tag', () {
      final release = model.parseTag('v5.4.1+3283')!;
      final patch = model.parseTag('v5.4.1+3283-p2')!;

      expect(release.version, version);
      expect(release.build, 3283);
      expect(release.isPatch, isFalse);
      expect(patch.version, version);
      expect(patch.build, 3283);
      expect(patch.patch, 2);
      expect(patch.isPatch, isTrue);
    });

    test('ignores tags of another shape', () {
      for (final name in [
        'archive/release/5.4.1',
        'v5.4.1',
        'v5.4+3',
        'v5.4.1+3283-x',
        'xv5.4.1+3283',
        'release-5.4.1',
      ]) {
        expect(model.parseTag(name), isNull, reason: name);
      }
    });

    test('escapes the literal parts of the pattern', () {
      const dotted = ReleaseModel(tagPattern: 'v.{version}.{build}');

      expect(dotted.parseTag('v.1.2.3.4')?.build, 4);
      expect(dotted.parseTag('vx1.2.3.4'), isNull);
    });
  });

  group('fromJson', () {
    test('takes a pattern and keeps the default for the others', () {
      final read = ReleaseModel.fromJson(const {
        'tagPattern': 'rel-{version}-{build}',
      });

      expect(read.tagPattern, 'rel-{version}-{build}');
      expect(read.branchPattern, ReleaseModel.defaultBranchPattern);
      expect(read.patchTagPattern, ReleaseModel.defaultPatchTagPattern);
    });

    test('rejects unknown keys and keys of the wrong type', () {
      expect(
        () => ReleaseModel.fromJson(const {'tagPatern': 'x'}),
        _formatError('Unknown release model key "tagPatern"'),
      );
      expect(
        () => ReleaseModel.fromJson(const {'tagPattern': 3}),
        _formatError('"tagPattern" must be a string'),
      );
    });

    test('rejects patterns that cannot name a release', () {
      final cases = <String, Map<String, dynamic>>{
        'tagPattern needs {build}': {'tagPattern': 'v{version}'},
        'tagPattern needs {version}': {'tagPattern': 'v{build}'},
        'branchPattern needs {version}': {'branchPattern': 'release'},
        'patchTagPattern needs {n}': {
          'patchTagPattern': 'v{version}+{build}-p',
        },
        'unknown placeholder {foo}': {
          'branchPattern': 'release/{foo}/{version}',
        },
        'more than once': {'branchPattern': '{version}/{version}'},
        'stray brace': {'branchPattern': 'release/{version}}'},
        'not a valid git ref name': {'branchPattern': 'release {version}'},
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(() => ReleaseModel.fromJson(value), _formatError(key));
      }
    });

    test('rejects names git refuses', () {
      for (final pattern in [
        'release/{version}/',
        '/release/{version}',
        '-release/{version}',
        'release..{version}',
        'release/{version}.lock',
        'release/{version}.',
        'release//{version}',
        'release/{version}~1',
        'release/{version}:x',
        r'release\{version}',
      ]) {
        expect(
          ReleaseModel(branchPattern: pattern).problems,
          isNotEmpty,
          reason: pattern,
        );
      }
    });

    test('lists every problem', () {
      expect(
        () => ReleaseModel.fromJson(const {
          'branchPattern': 'x',
          'tagPattern': 'y',
        }),
        _formatError('branchPattern needs {version}. tagPattern needs'),
      );
    });
  });
}

Matcher _formatError(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(message)),
);
