import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_fake_asc/xp_fake_asc.dart';

/// Serves the fake App Store Connect for an end-to-end script until it gets
/// SIGTERM or SIGINT (`tool/e2e/web_e2e.sh`).
///
///     dart run bin/serve.dart <key file> [--certificates=<n>] [<bundle id> ...]
///
/// It writes the private key of the test key (which only this fake trusts)
/// to `<key file>`, knows an app for each `<bundle id>`, and starts with `n`
/// distribution certificates of the team. Then it prints `url=`, `keyId=`
/// and `issuerId=` lines, the address first.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'usage: serve.dart <key file> [--certificates=<n>] [<bundle id> ...]',
    );
    exitCode = 64;
    return;
  }
  final keyFile = File(arguments.first);
  await keyFile.writeAsString(fakeAscPrivateKeyPem);
  await Process.run('chmod', ['600', keyFile.path]);

  final server = await FakeAscServer.start();
  for (final argument in arguments.skip(1)) {
    if (argument.startsWith('--certificates=')) {
      final count = int.parse(argument.substring('--certificates='.length));
      for (var i = 1; i <= count; i++) {
        server.certificates['seeded-$i'] = FakeAscCertificate(
          id: 'seeded-$i',
          serialNumber: '5EED0$i',
          certificateType: 'DISTRIBUTION',
          content: base64.decode(fakeDistributionCertificate),
          name: 'Apple Distribution: Fake Team $i',
        );
      }
    } else {
      server.addApp(argument);
    }
  }
  stdout
    ..writeln('url=${server.baseUrl}')
    ..writeln('keyId=$fakeAscKeyId')
    ..writeln('issuerId=$fakeAscIssuerId');

  await Future.any([
    ProcessSignal.sigterm.watch().first,
    ProcessSignal.sigint.watch().first,
  ]);
  await server.close();
  // The other signal's watch would keep the VM alive.
  exit(0);
}
