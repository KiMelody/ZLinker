// Review screen recording: drives the real app UI through its core flow
// (device list → task list → conversation) while `adb screenrecord` captures
// the device display. Run via flutter drive; recording is started/stopped
// on the host, this script only produces the on-device interactions.
//
//   ZLINKER_SHOT_DIR=build flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/review_recording_test.dart -d <device> \
//     --dart-define=SHOT_LOCALE=zh-CN
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zlinker/notifications/keepalive_controller.dart';
import 'package:zlinker/state/device_session.dart';
import 'package:zlinker/state/device_store.dart';
import 'package:zlinker/state/scheduled_store.dart';
import 'package:zlinker/ui/devices_page.dart';
import 'package:zlinker/ui/theme.dart';
import 'package:zlinker/ui/ui_settings.dart';

import '../test/helpers/fake_device_session.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

final _sessions = [
  {
    'sessionId': 'sess_rec_1',
    'title': 'ZLinker 商店页文案与截图',
    'phase': 'running',
    'lastAssistantPreview': '截图测试已通过，正在生成双语言商店素材…',
    'lastActivityAt': _now - 1000 * 62,
    'pinned': true,
  },
  {
    'sessionId': 'sess_rec_2',
    'title': '深度解析 GitHub 描述生成',
    'phase': 'completed',
    'lastAssistantPreview': '完整分析已输出，共三个结论。',
    'lastActivityAt': _now - 1000 * 60 * 41,
  },
  {
    'sessionId': 'sess_rec_3',
    'title': '闲时任务：每日构建巡检报告',
    'phase': 'queued',
    'lastAssistantPreview': '排队中 · 预计 02:00 空闲窗口执行',
    'lastActivityAt': _now - 1000 * 60 * 60 * 5,
  },
];

final _workspaces = [
  {'workspacePath': '/Users/dev/ZLinker', 'workspaceIdentity': 'ZLinker'},
];

final _chatRows = [
  {'rowId': 1, 'kind': 'userInput', 'text': '帮我把任务列表按置顶分组重排'},
  {
    'rowId': 2,
    'kind': 'assistantText',
    'text': '已完成重排：\n\n- **已置顶** 分组现在排在最前\n- 每组内按最近活动时间排序\n- 运行中的任务带实时状态点',
  },
  {
    'rowId': 3,
    'kind': 'turnHeader',
    'state': 'completedSuccess',
    'activeMs': 48000,
    'fileChanges': {'files': 2, 'additions': 64, 'deletions': 11},
  },
];

Widget _wrap(Widget child, ThemeController theme, UiSettings ui) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      builder: (context, child) =>
          UiSettingsProvider(settings: ui, child: child!),
      home: child,
    );

class _RecHub extends DeviceSessionHub {
  final Map<String, DeviceSession> fakes;
  _RecHub(this.fakes) : super(nativeListEnabled: () => true);

  @override
  void syncWith(List<Device> devices) {}
  @override
  DeviceSession? ensure(Device device) => fakes[device.id];
  @override
  DeviceSession? sessionOf(String deviceId) => fakes[deviceId];
  @override
  Future<void> suspend(String deviceId) async {}
  @override
  void scheduleResume(Device device) {}
  @override
  Future<void> disconnectAll() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record review flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController();
    final ui = UiSettings()..locale = 'zh-CN';
    final store = DeviceStore();
    await store.load();
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=abc&hash=xyz&t=123&mid=m1&name=Mac%20Studio&app_version=3.8.1');
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=def&hash=uvw&t=124&mid=m2&name=ThinkPad&app_version=3.8.1');
    final deviceA = store.devices.first;

    final session = FakeDeviceSession(
      deviceId: deviceA.id,
      params: deviceA.params!,
      entries: _sessions,
      workspaces: _workspaces,
      chatRows: _chatRows,
    );
    final sessionB = FakeDeviceSession(
      deviceId: store.devices[1].id,
      params: store.devices[1].params!,
      entries: _sessions,
    );
    final hub = _RecHub({deviceA.id: session, store.devices[1].id: sessionB});

    // 1. Device list — linger so the recording shows the starting state.
    await tester.pumpWidget(_wrap(
      DevicesPage(
        store: store,
        theme: theme,
        ui: ui,
        hub: hub,
        scheduled: ScheduledStore(),
        keepalive: KeepAliveController(),
      ),
      theme,
      ui,
    ));
    await tester.pump(const Duration(seconds: 3));

    // 2. Tap the Mac Studio card → task list.
    await tester.tap(find.text('Mac Studio'));
    await tester.pump(const Duration(seconds: 3));

    // 3. Tap the pinned task → conversation with streaming reply.
    await tester.tap(find.text('ZLinker 商店页文案与截图').first);
    await tester.pump(const Duration(seconds: 4));

    // 4. Scroll the conversation so the reply and file-change bar are visible.
    final list = find.byType(Scrollable).last;
    await tester.drag(list, const Offset(0, -300));
    await tester.pump(const Duration(seconds: 3));
  });
}
