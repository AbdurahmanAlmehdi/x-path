import 'dart:convert';
import 'dart:io';

/// Where the altool output is.
const altoolFixtureDirectory = 'test/src/stores/apple/fixtures';

/// The lines of the altool output [name].
List<String> altoolFixture(String name) => const LineSplitter().convert(
  File('$altoolFixtureDirectory/$name').readAsStringSync(),
);
