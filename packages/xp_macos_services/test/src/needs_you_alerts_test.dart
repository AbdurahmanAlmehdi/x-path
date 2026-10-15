import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

const _notice = ApprovalNotice(
  approvalId: 'apr_1',
  title: 'Submit 5.4.1 (3283) to the stores',
  body: 'mataa_new_app · prod · 9a3bc0d · expires in 23h 51m',
  review: 'Review…',
  later: 'Later',
);

const _menu = MenuBarContent(
  tooltip: 'XPath: 1 needs you',
  header: 'Needs you · 1',
  items: [
    MenuBarItem(
      approvalId: 'apr_1',
      title: 'Review: Submit 5.4.1 (3283)…',
      detail: 'mataa_new_app · prod',
    ),
  ],
  openApp: 'Open XPath',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(needsYouChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Sends [method] from the runner to the Dart side.
  Future<void> fromRunner(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
        needsYouChannelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );

  test('the channel is namespaced under ly.abdurahman.xpath', () {
    expect(needsYouChannelName, 'ly.abdurahman.xpath/needs_you');
  });

  test('the values compare by value', () {
    expect(_notice.props, hasLength(5));
    expect(_menu.items.single.props, hasLength(3));
    expect(_menu.props, hasLength(4));
    expect(const ReviewApproval('a'), const ReviewApproval('a'));
    expect(const ShowApproval('a').props, ['a']);
    expect(const OpenApp().props, isEmpty);
    expect(_menu.needsYou, isTrue);
  });

  group('MethodChannelNeedsYouAlerts', () {
    test('sends notices, withdrawals and the menu to the runner', () async {
      final alerts = MethodChannelNeedsYouAlerts();
      await alerts.notify(_notice);
      await alerts.withdraw('apr_1');
      await alerts.updateMenuBar(_menu);
      expect(calls.map((call) => call.method), [
        'notify',
        'withdraw',
        'menuBar',
      ]);
      expect(calls[0].arguments, {
        'id': 'apr_1',
        'title': 'Submit 5.4.1 (3283) to the stores',
        'body': 'mataa_new_app · prod · 9a3bc0d · expires in 23h 51m',
        'review': 'Review…',
        'later': 'Later',
      });
      expect(calls[1].arguments, {'id': 'apr_1'});
      expect(calls[2].arguments, {
        'tooltip': 'XPath: 1 needs you',
        'header': 'Needs you · 1',
        'needsYou': true,
        'openApp': 'Open XPath',
        'items': [
          {
            'id': 'apr_1',
            'title': 'Review: Submit 5.4.1 (3283)…',
            'detail': 'mataa_new_app · prod',
          },
        ],
      });
    });

    test('passes on what the owner clicked, never a decision', () async {
      final alerts = MethodChannelNeedsYouAlerts();
      final actions = <NeedsYouAction>[];
      final subscription = alerts.actions.listen(actions.add);
      await fromRunner('review', {'id': 'apr_1'});
      await fromRunner('show', {'id': 'apr_2'});
      await fromRunner('open');
      await fromRunner('review');
      await fromRunner('approve', {'id': 'apr_1'});
      await subscription.cancel();
      expect(actions, const [
        ReviewApproval('apr_1'),
        ShowApproval('apr_2'),
        OpenApp(),
      ]);
    });
  });

  test('FakeNeedsYouAlerts records and plays clicks', () async {
    final alerts = FakeNeedsYouAlerts();
    final actions = <NeedsYouAction>[];
    final subscription = alerts.actions.listen(actions.add);
    await alerts.notify(_notice);
    await alerts.withdraw('apr_1');
    await alerts.updateMenuBar(_menu);
    alerts.act(const OpenApp());
    await pumpEventQueue();
    await subscription.cancel();
    expect(alerts.notices, [_notice]);
    expect(alerts.withdrawn, ['apr_1']);
    expect(alerts.menus, [_menu]);
    expect(actions, const [OpenApp()]);
  });
}
