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

const _engineNotice = EngineNotice(
  target: 'job:job_1',
  title: 'Job failed',
  body: 'Build prod',
);

const _running = MenuBarRun(
  target: 'run:run_1:prj_1',
  title: 'Prod release 5.4.1',
  detail: 'mataa · 3 of 5 jobs',
);

const _project = MenuBarProject(projectId: 'prj_1', name: 'mataa');

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
    expect(_menu.props, hasLength(8));
    expect(_engineNotice.props, ['job:job_1', 'Job failed', 'Build prod']);
    expect(_running.props, hasLength(3));
    expect(_project.props, ['prj_1', 'mataa']);
    expect(const ShowNotice('runners').props, ['runners']);
    expect(const DispatchProject('prj_1').props, ['prj_1']);
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
      await alerts.notifyNotice(_engineNotice);
      await alerts.updateMenuBar(
        const MenuBarContent(
          tooltip: 't',
          header: 'h',
          items: [],
          openApp: 'o',
          runningHeader: 'Running · 1',
          running: [_running],
          dispatch: 'Dispatch…',
          projects: [_project],
        ),
      );
      expect(calls.map((call) => call.method), [
        'notify',
        'withdraw',
        'menuBar',
        'notice',
        'menuBar',
      ]);
      expect(calls[3].arguments, {
        'id': 'notice:job:job_1',
        'title': 'Job failed',
        'body': 'Build prod',
      });
      expect(calls[4].arguments, {
        'tooltip': 't',
        'header': 'h',
        'needsYou': false,
        'openApp': 'o',
        'items': <Object?>[],
        'runningHeader': 'Running · 1',
        'running': [
          {
            'id': 'notice:run:run_1:prj_1',
            'title': 'Prod release 5.4.1',
            'detail': 'mataa · 3 of 5 jobs',
          },
        ],
        'dispatch': 'Dispatch…',
        'projects': [
          {'id': 'prj_1', 'title': 'mataa'},
        ],
      });
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
        'running': <Object?>[],
        'projects': <Object?>[],
      });
    });

    test('passes on what the owner clicked, never a decision', () async {
      final alerts = MethodChannelNeedsYouAlerts();
      final actions = <NeedsYouAction>[];
      final subscription = alerts.actions.listen(actions.add);
      await fromRunner('review', {'id': 'apr_1'});
      await fromRunner('show', {'id': 'apr_2'});
      await fromRunner('open');
      await fromRunner('show', {'id': 'notice:job:job_1'});
      await fromRunner('dispatch', {'id': 'prj_1'});
      await fromRunner('review');
      await fromRunner('approve', {'id': 'apr_1'});
      await subscription.cancel();
      expect(actions, const [
        ReviewApproval('apr_1'),
        ShowApproval('apr_2'),
        OpenApp(),
        ShowNotice('job:job_1'),
        DispatchProject('prj_1'),
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
    await alerts.notifyNotice(_engineNotice);
    alerts.act(const OpenApp());
    await pumpEventQueue();
    await subscription.cancel();
    expect(alerts.notices, [_notice]);
    expect(alerts.withdrawn, ['apr_1']);
    expect(alerts.menus, [_menu]);
    expect(alerts.engineNotices, [_engineNotice]);
    expect(actions, const [OpenApp()]);
  });
}
