import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

const _flutter = ResolvedFlutter(
  path: '/sdk',
  version: '3.47.6',
  dartVersion: '3.13.5',
  source: FlutterSource.fvm,
);

void main() {
  group('JobTools.from', () {
    test('takes the Flutter SDK and the tools that are available', () {
      final tools = JobTools.from(
        flutter: _flutter,
        reports: const <ToolReport>[
          ToolReport('shorebird', ToolStatus.available, version: '1.6.128'),
          ToolReport('gh', ToolStatus.available, version: '2.96.0'),
          ToolReport('xcode', ToolStatus.available, version: '27.1'),
        ],
      );

      expect(
        tools,
        const JobTools(
          flutter: '3.47.6',
          dart: '3.13.5',
          shorebird: '1.6.128',
          gh: '2.96.0',
          xcode: '27.1',
        ),
      );
    });

    test('leaves out what is missing, as on Linux', () {
      final tools = JobTools.from(
        flutter: _flutter,
        reports: const <ToolReport>[
          ToolReport('shorebird', ToolStatus.missing),
          ToolReport('gh', ToolStatus.available, version: '2.96.0'),
          ToolReport('xcode', ToolStatus.unsupported),
        ],
      );

      expect(
        tools,
        const JobTools(flutter: '3.47.6', dart: '3.13.5', gh: '2.96.0'),
      );
    });

    test('is empty without anything', () {
      expect(JobTools.from(), const JobTools());
    });
  });

  group('JobTools JSON', () {
    test('round-trips and leaves out what is absent', () {
      const tools = JobTools(flutter: '3.47.6', gh: '2.96.0');

      expect(tools.toJson(), {'flutter': '3.47.6', 'gh': '2.96.0'});
      expect(JobTools.fromJson(tools.toJson()), tools);
      expect(JobTools.fromJson(const {}), const JobTools());
      const linux = JobTools(iosLinux: 'Linux, omarchy-apple-dev abc');
      expect(linux.toJson(), {'iosLinux': 'Linux, omarchy-apple-dev abc'});
      expect(JobTools.fromJson(linux.toJson()), linux);
    });

    test('ignores unknown keys and rejects a field that is not text', () {
      const json = {'flutter': '1', 'later': 3};
      expect(JobTools.fromJson(json).flutter, '1');
      expect(
        () => JobTools.fromJson(const {'flutter': 3}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
