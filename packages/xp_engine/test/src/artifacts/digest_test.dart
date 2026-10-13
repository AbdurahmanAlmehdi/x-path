import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const abc =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  test('hashes bytes', () {
    expect(sha256OfBytes(utf8.encode('abc')), abc);
  });

  test('hashes a stream in chunks', () async {
    expect(
      await sha256OfStream(
        Stream.fromIterable([utf8.encode('a'), utf8.encode('bc')]),
      ),
      abc,
    );
  });
}
