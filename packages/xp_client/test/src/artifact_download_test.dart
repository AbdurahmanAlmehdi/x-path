import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';
import 'package:xp_client/xp_client.dart';

void main() {
  late Directory directory;
  late File target;
  final bytes = utf8.encode('the artifact');
  final digest = crypto.sha256.convert(bytes).toString();

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_client_download');
    target = File('${directory.path}/app.apk');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  ArtifactDownload download({
    Stream<List<int>>? content,
    String? sha256,
    int? length,
  }) => ArtifactDownload(
    content: content ?? Stream.value(bytes),
    sha256: sha256,
    length: length,
  );

  group('saveTo', () {
    test('writes the file and returns its SHA-256', () async {
      final saved = await download(
        sha256: digest,
        length: bytes.length,
      ).saveTo(target);

      expect(saved, digest);
      expect(target.readAsBytesSync(), bytes);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('without announcements takes what comes', () async {
      final saved = await download().saveTo(target);

      expect(saved, digest);
    });

    test('refuses a file with another SHA-256 and leaves nothing', () async {
      await expectLater(
        download(sha256: 'f' * 64).saveTo(target),
        throwsA(isA<DownloadException>()),
      );

      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('refuses a file of another size and leaves nothing', () async {
      await expectLater(
        download(length: 1).saveTo(target),
        throwsA(isA<DownloadException>()),
      );

      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('reports a download that breaks off and leaves nothing', () async {
      Stream<List<int>> broken() async* {
        yield [1, 2, 3];
        throw const SocketException('reset');
      }

      await expectLater(
        download(content: broken()).saveTo(target),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('broke off'),
          ),
        ),
      );

      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });
  });
}
