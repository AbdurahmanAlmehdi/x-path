import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scan/scan_context.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  ScanContext contextOf(Map<String, String> files) =>
      ScanContext(InMemoryScanSource(files));

  group('yaml', () {
    test('reads a mapping', () async {
      final context = contextOf({'a.yaml': 'k: v'});

      expect((await context.yaml('a.yaml'))!['k'], 'v');
    });

    test('is null for a missing file, an empty file and a list', () async {
      final context = contextOf({'empty.yaml': '', 'list.yaml': '- a'});

      expect(await context.yaml('missing.yaml'), isNull);
      expect(await context.yaml('empty.yaml'), isNull);
      expect(await context.yaml('list.yaml'), isNull);
    });

    test('reports a syntax error to the callback, once', () async {
      final context = contextOf({'bad.yaml': 'a: [b'});
      final errors = <String>[];

      expect(await context.yaml('bad.yaml', invalid: errors.add), isNull);
      expect(errors, hasLength(1));
    });

    test('stays quiet about a syntax error without a callback', () async {
      final context = contextOf({'bad.yaml': 'a: [b'});

      expect(await context.yaml('bad.yaml'), isNull);
      expect(context.findings, isEmpty);
    });
  });

  group('add', () {
    test('records findings in order', () {
      final context = contextOf({})
        ..add(FindingSeverity.info, 'a', 'm', 'f')
        ..add(FindingSeverity.error, 'b', 'm', 'f', path: 'p', app: 'x');

      expect(context.findings.map((finding) => finding.code), ['a', 'b']);
      expect(context.findings.last.path, 'p');
      expect(context.findings.last.app, 'x');
    });
  });

  group('pin', () {
    test('prefers the pin of the app to that of the repository', () async {
      final context = contextOf({
        '.fvmrc': '{"flutter": "3.0.0"}',
        'apps/a/.fvmrc': '{"flutter": "3.1.0"}',
      });

      final pin = await context.pin('apps/a');

      expect(pin!.version, '3.1.0');
      expect(pin.source, 'apps/a/.fvmrc');
      expect((await context.pin('apps/b'))!.source, '.fvmrc');
      expect((await context.pin(''))!.version, '3.0.0');
    });

    test('is null without any .fvmrc', () async {
      expect(await contextOf({}).pin('apps/a'), isNull);
    });

    test('drops a channel from a version', () async {
      final context = contextOf({'.fvmrc': '{"flutter": "3.47.4@stable"}'});

      expect((await context.pin(''))!.version, '3.47.4');
      expect(context.findings, isEmpty);
    });

    test('accepts a pre-release version', () async {
      final context = contextOf({'.fvmrc': '{"flutter": "3.50.0-0.1.pre"}'});

      expect((await context.pin(''))!.version, '3.50.0-0.1.pre');
      expect(context.findings, isEmpty);
    });

    test('warns about a channel instead of a version', () async {
      final context = contextOf({'.fvmrc': '{"flutter": "stable"}'});

      final pin = await context.pin('');

      expect(pin!.version, 'stable');
      expect(context.findings.single.code, 'fvmrc_not_exact');
      expect(context.findings.single.severity, FindingSeverity.warning);
    });

    test('reports a file that is not a version pin, with no version', () async {
      for (final text in ['not json', '[1]', '{"flutter": 3}', '{}']) {
        final context = contextOf({'.fvmrc': text});

        final pin = await context.pin('');

        expect(pin!.version, isNull, reason: text);
        expect(pin.source, '.fvmrc');
        expect(context.findings.single.code, 'fvmrc_invalid', reason: text);
        expect(context.findings.single.severity, FindingSeverity.error);
      }
    });

    test('reads and reports each file once', () async {
      final context = contextOf({'.fvmrc': 'broken'});

      await context.pin('apps/a');
      await context.pin('apps/b');
      await context.pin('');

      expect(context.findings, hasLength(1));
    });
  });
}
