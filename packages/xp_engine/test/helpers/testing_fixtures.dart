import 'dart:convert';
import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// Where the captured tool output is.
const fixtureDirectory = 'test/src/testing/fixtures';

/// The app directory the captured runs were made in (the machine's own
/// directory was replaced by this one).
const capturedAppDirectory = '/work/app';

/// The lines of the captured output [name].
List<String> fixtureLines(String name) => const LineSplitter().convert(
  File('$fixtureDirectory/$name').readAsStringSync(),
);

/// Reads the captured `flutter test --machine` output [name].
ParsedTestRun parseCapturedRun(String name) {
  final parser = MachineTestParser(appDirectory: capturedAppDirectory);
  fixtureLines(name).forEach(parser.addLine);
  return parser.finish()!;
}
