import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

const _pem =
    '-----BEGIN PRIVATE KEY-----\n'
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n'
    'KcwggSjAgEAAoIBAQC7VJTUt9Us8cKj\n'
    '-----END PRIVATE KEY-----\n';

void main() {
  group('mask', () {
    test('replaces a secret wherever it occurs', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      expect(masker.mask('a hunter2hunter2 b hunter2hunter2'), 'a *** b ***');
    });

    test('leaves text without a secret alone', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      expect(masker.mask('nothing to see'), 'nothing to see');
      expect(masker.mask(''), '');
    });

    test('masks nothing when it knows no secret', () {
      expect(SecretMasker().mask('anything at all'), 'anything at all');
    });

    test('uses the given replacement', () {
      final masker = SecretMasker(
        secrets: ['hunter2hunter2'],
        replacement: '[redacted]',
      );

      expect(masker.mask('x hunter2hunter2'), 'x [redacted]');
    });

    test('masks secrets added later', () {
      final masker = SecretMasker()..add('late-secret-value');

      expect(masker.mask('is late-secret-value here'), 'is *** here');
    });

    test('treats regular expression characters literally', () {
      final masker = SecretMasker(secrets: [r'a.b*c+(d)[e]$^|\']);

      expect(masker.mask(r'x a.b*c+(d)[e]$^|\ y aXbbbc'), 'x *** y aXbbbc');
    });
  });

  group('short values', () {
    test('are not masked below the minimum length', () {
      final masker = SecretMasker(secrets: ['12345', 'true', '']);

      expect(masker.mask('12345 true'), '12345 true');
    });

    test('are masked from the minimum length on', () {
      expect(SecretMasker.defaultMinLength, 6);
      final masker = SecretMasker(secrets: ['123456']);

      expect(masker.mask('x 123456 y'), 'x *** y');
    });

    test('use the minimum length of the masker', () {
      final masker = SecretMasker(secrets: ['abcd'], minLength: 4);

      expect(masker.mask('abcd'), '***');
    });

    test('are measured after trimming', () {
      final masker = SecretMasker(secrets: ['   abc   ']);

      expect(masker.mask('abc   abc'), 'abc   abc');
    });
  });

  group('multi-line secrets', () {
    test('are masked line by line', () {
      final masker = SecretMasker(secrets: [_pem]);

      final output = masker.mask(
        'key follows\n'
        'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n'
        'other line\n'
        'KcwggSjAgEAAoIBAQC7VJTUt9Us8cKj\n',
      );

      expect(output, 'key follows\n***\nother line\n***\n');
    });

    test('are masked as a whole when echoed whole', () {
      final masker = SecretMasker(secrets: [_pem]);

      expect(masker.mask(_pem), '***\n***\n***\n***\n');
    });

    test('are masked when the output is indented or has CRLF endings', () {
      final masker = SecretMasker(secrets: [_pem]);

      final output = masker.mask(
        '    MIIEvQIBADANBgkqhkiG9w0BAQEFAASC\r\n'
        '\tKcwggSjAgEAAoIBAQC7VJTUt9Us8cKj\r\n',
      );

      expect(output, '    ***\r\n\t***\r\n');
    });

    test('ignore short lines such as braces', () {
      final masker = SecretMasker(
        secrets: ['{\n  "private_key": "abcdefghijkl"\n}'],
      );

      expect(masker.mask('{ } {'), '{ } {');
      expect(masker.mask('  "private_key": "abcdefghijkl"'), '  ***');
    });
  });

  group('overlapping secrets', () {
    test('mask the longer one first', () {
      final masker = SecretMasker(
        secrets: ['password', 'password-with-suffix'],
      );

      expect(masker.mask('is password-with-suffix!'), 'is ***!');
    });

    test('merge when they overlap, leaving no tail showing', () {
      final masker = SecretMasker(secrets: ['abcdefgh', 'efghijkl']);

      expect(masker.mask('x abcdefghijkl y'), 'x *** y');
    });

    test('mask each match when they only touch', () {
      final masker = SecretMasker(secrets: ['abcdefgh', 'ijklmnop']);

      expect(masker.mask('abcdefghijklmnop'), '***');
    });

    test('mask a secret inside another secret once', () {
      final masker = SecretMasker(secrets: ['abcdefghij', 'cdefgh']);

      expect(masker.mask('abcdefghij'), '***');
    });

    test('find a secret that overlaps itself', () {
      final masker = SecretMasker(secrets: ['aaaaaaa']);

      expect(masker.mask('aaaaaaaaa'), '***');
    });
  });

  group('MaskingStream', () {
    List<String> run(SecretMasker masker, List<String> pieces) {
      final stream = MaskingStream(masker);
      return [...pieces.map(stream.add), stream.flush()];
    }

    test('masks a secret inside one piece', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      expect(run(masker, ['a hunter2hunter2 b']).join(), 'a *** b');
    });

    test('masks a secret split between two pieces', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      final out = run(masker, ['before hunter2', 'hunter2 after']);

      expect(out.join(), 'before *** after');
      expect(out.join(), isNot(contains('hunter')));
    });

    test('never emits a piece of a secret that is still arriving', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);
      final stream = MaskingStream(masker);

      expect(stream.add('say hun'), 'say ');
      expect(stream.add('ter2hunt'), '');
      expect(stream.add('er2 now'), '*** now');
      expect(stream.flush(), '');
    });

    test('masks a secret split at every possible position', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);
      const text = 'x hunter2hunter2 y';

      for (var cut = 0; cut <= text.length; cut++) {
        final out = run(masker, [text.substring(0, cut), text.substring(cut)]);

        expect(out.join(), 'x *** y', reason: 'cut at $cut');
      }
    });

    test('masks a secret delivered one character at a time', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      final out = run(masker, 'a hunter2hunter2 b'.split(''));

      expect(out.join(), 'a *** b');
    });

    test('releases held text that turns out not to be a secret', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);
      final stream = MaskingStream(masker);

      expect(stream.add('hunter2'), '');
      expect(stream.add(' is not it'), 'hunter2 is not it');
    });

    test('flush masks and releases what is still held', () {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);
      final stream = MaskingStream(masker);

      expect(stream.add('ends with hunter2'), 'ends with ');
      expect(stream.flush(), 'hunter2');
      expect(stream.flush(), '');
    });

    test('flush masks a complete secret that was held back', () {
      final masker = SecretMasker(secrets: ['abcdef', 'abcdefg']);
      final stream = MaskingStream(masker);

      expect(stream.add('x abcdef'), 'x ');
      expect(stream.flush(), '***');
    });

    test('masks a multi-line secret split across pieces', () {
      final masker = SecretMasker(secrets: [_pem]);

      final out = run(masker, [
        'MIIEvQIBADANBgkqhk',
        'iG9w0BAQEFAASC\nKcwggSjAgEAAo',
        'IBAQC7VJTUt9Us8cKj\n',
      ]);

      expect(out.join(), '***\n***\n');
    });

    test('holds a complete match back while a longer secret may follow', () {
      final masker = SecretMasker(secrets: ['password', 'password-longer']);
      final stream = MaskingStream(masker);

      expect(stream.add('a password'), 'a ');
      expect(stream.add('-longer b'), '*** b');
    });

    test('holds a match whose tail may begin another secret', () {
      final masker = SecretMasker(secrets: ['abcdefgh', 'efghijkl']);
      final stream = MaskingStream(masker);

      expect(stream.add('x abcdefgh'), 'x ');
      expect(stream.add('ijkl y'), '*** y');
    });

    test('masks several secrets in one piece', () {
      final masker = SecretMasker(secrets: ['first-secret', 'second-secret']);

      expect(
        run(masker, ['first-secret and second-secret']).join(),
        '*** and ***',
      );
    });

    test('picks up a secret added while the stream is running', () {
      final masker = SecretMasker();
      final stream = MaskingStream(masker);

      expect(stream.add('one late-secret-value'), 'one late-secret-value');
      masker.add('late-secret-value');

      expect(stream.add(' two late-secret-value'), ' two ***');
    });

    test('passes text through when there are no secrets', () {
      final stream = MaskingStream(SecretMasker());

      expect(stream.add('plain'), 'plain');
      expect(stream.flush(), '');
    });
  });

  group('maskStream', () {
    test('masks a secret split across chunks and ends with the rest', () async {
      final masker = SecretMasker(secrets: ['hunter2hunter2']);

      final out = await masker
          .maskStream(
            Stream.fromIterable(['log hunter', '2hunter2 ', 'done hunter2']),
          )
          .toList();

      // The last "hunter2" is only half a secret: it is released unmasked.
      expect(out.join(), 'log *** done hunter2');
      expect(out, isNot(contains('')));
    });

    test('is empty for an empty stream', () async {
      final out = await SecretMasker()
          .maskStream(const Stream.empty())
          .toList();

      expect(out, isEmpty);
    });
  });

  group('as an OutputMasker', () {
    test('masks, through a stream per output stream, what it learned', () {
      final OutputMasker masker = SecretMasker()..add('hunter2hunter2');
      final stdout = masker.newStream();
      final stderr = masker.newStream();

      expect(stdout.add('log hunter'), 'log ');
      expect(stderr.add('plain hunter2hunter2 x'), 'plain *** x');
      expect(stdout.add('2hunter2 ok'), '*** ok');
      expect(stdout.flush(), isEmpty);
      expect(stderr.flush(), isEmpty);
    });
  });
}
