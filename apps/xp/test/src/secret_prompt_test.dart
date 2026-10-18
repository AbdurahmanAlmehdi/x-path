import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/secret_prompt.dart';

class _MockStdin extends Mock implements Stdin;

class _MockSink extends Mock implements IOSink;

void main() {
  late _MockStdin stdin;
  late _MockSink stderr;
  late TerminalSecretPrompt prompt;

  setUp(() {
    stdin = _MockStdin();
    stderr = _MockSink();
    prompt = TerminalSecretPrompt(stdin: stdin, stderr: stderr);
    when(() => stdin.echoMode).thenReturn(true);
  });

  test('is interactive when standard input is a terminal', () {
    when(() => stdin.hasTerminal).thenReturn(true);
    expect(prompt.interactive, isTrue);

    when(() => stdin.hasTerminal).thenReturn(false);
    expect(prompt.interactive, isFalse);
  });

  test('asks on standard error and reads a line with the echo off', () {
    when(() => stdin.readLineSync()).thenReturn('hunter2');

    expect(prompt.ask('Password'), 'hunter2');

    verifyInOrder([
      () => stderr.write('Password: '),
      () => stdin.echoMode = false,
      () => stdin.readLineSync(),
      () => stdin.echoMode = true,
      () => stderr.writeln(),
    ]);
  });

  test('turns the echo back on when reading fails, and reads nothing at '
      'the end of input', () {
    when(() => stdin.readLineSync()).thenThrow(const StdinException('gone'));

    expect(() => prompt.ask('Password'), throwsA(isA<StdinException>()));
    verify(() => stdin.echoMode = true).called(1);

    when(() => stdin.readLineSync()).thenReturn(null);
    expect(prompt.ask('Password'), '');
  });

  test("uses the process's streams by default", () {
    expect(const TerminalSecretPrompt().interactive, isA<bool>());
  });
}
