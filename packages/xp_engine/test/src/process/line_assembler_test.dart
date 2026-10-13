import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late LineAssembler assembler;

  setUp(() => assembler = LineAssembler(maxLength: 10));

  test('returns the lines a piece completes', () {
    expect(assembler.add('one\ntwo\nthr'), ['one', 'two']);
    expect(assembler.add('ee\n'), ['three']);
  });

  test('ends lines at CRLF and at a lone CR', () {
    expect(assembler.add('a\r\nb\rc\n'), ['a', 'b', 'c']);
  });

  test('treats a CRLF that is split between pieces as one ending', () {
    expect(assembler.add('a\r'), ['a']);
    expect(assembler.add('\nb\n'), ['b']);
  });

  test('keeps empty lines', () {
    expect(assembler.add('a\n\nb\n'), ['a', '', 'b']);
  });

  test('cuts a line at the maximum length', () {
    expect(assembler.add('0123456789abc'), ['0123456789']);
    expect(assembler.add('def\n'), ['abcdef']);
  });

  test('does not emit an empty line after a cut at the very end', () {
    expect(assembler.add('0123456789\nnext\n'), ['0123456789', 'next']);
  });

  test('flushes the unfinished line, once', () {
    assembler.add('rest');

    expect(assembler.flush(), 'rest');
    expect(assembler.flush(), isNull);
  });

  test('has nothing to flush after a complete line', () {
    assembler.add('done\n');

    expect(assembler.flush(), isNull);
  });

  test('has a default maximum length', () {
    expect(LineAssembler().maxLength, LineAssembler.defaultMaxLength);
  });
}
