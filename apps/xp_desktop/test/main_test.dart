import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/main.dart' as app;
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'helpers/pump_app.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  new(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory support;
  late PathProviderPlatform original;

  setUp(() {
    support = Directory.systemTemp.createTempSync('xp_support_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(macosServicesChannel, (call) async => null);
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(macosServicesChannel, null);
    support.deleteSync(recursive: true);
  });

  testWidgets('main starts the app on this Mac', (tester) async {
    final onError = FlutterError.onError;
    final observer = Bloc.observer;
    addTearDown(() {
      FlutterError.onError = onError;
      Bloc.observer = observer;
    });
    desktopWindow(tester);

    await tester.runAsync(() async {
      await app.main();
      expect(FlutterError.onError, isNot(onError));
      FlutterError.onError = onError;
      // The engine list is a file: let the real event loop read it.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('Set up XPath on this Mac'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('the services of this Mac live in its support folder', () async {
    final services = await AppServices.system();
    expect(services.engines.directory, support.path);
    expect(services.agent, isA<MethodChannelEngineAgent>());
    expect(services.linker, isA<FileSystemCliLinker>());
    expect(services.tools, isA<PathToolChecker>());
    expect(services.localEngine, isA<BundledLocalEngine>());
    expect(services.deviceName, isNotEmpty);
    final session = services.openSession(EngineProfileForTest.profile, 'xpt_1');
    expect(session.profile, EngineProfileForTest.profile);
    session.client.close();
  });
}

abstract final class EngineProfileForTest {
  static final profile = EngineProfile(
    id: 'mac-mini:7480',
    name: 'mac-mini',
    url: Uri.parse('http://mac-mini:7480'),
  );
}
