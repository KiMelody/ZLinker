import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): 3.12.3 protocol-drift verification round.
/// Read-only calls; bogus ids distinguish "method exists but rejected"
/// (validation error) from "no such method" (method removed).
///
/// Covers the open questions from the 2026-09-17 static binary diff:
///  A. zcode-task: prepareWorkspace removal + getTaskConfigOptions family
///  B. automation: listAllAutomations survival + setAutomationEnabled
///  C. off-peak-task channel method surface (expected: all missing)
///  D. provider-settings / model-selection channels (model-provider
///     replacement) method discovery
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live 3.12.3 drift probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123', params: params);

    Future<void> tryCall(String channel, String method,
        [List<Object?> args = const []]) async {
      try {
        final res = await session.callChannel(channel, method, args);
        String brief;
        if (res is Map) {
          brief = 'keys=${res.keys.take(10).toList()}';
        } else if (res is List) {
          brief = 'listLen=${res.length}';
        } else {
          brief = '$res';
        }
        // ignore: avoid_print
        print('PROBE HIT  $channel.$method -> $brief');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE miss $channel.$method: $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // A real task scope for task-scoped calls (getTaskConfigOptions etc.).
      final live = session.sessions?.list ?? const [];
      final relay = session.relayTasks;
      final String? taskId =
          live.isNotEmpty ? live.first.sessionId : (relay.isNotEmpty ? '${relay.first['taskId']}' : null);
      final String? wsPath = relay.isNotEmpty
          ? '${relay.first['workspacePath']}'
          : null;
      final Map<String, dynamic> scope = {
        if (wsPath != null) 'workspacePath': wsPath,
        if (relay.isNotEmpty && relay.first['workspaceIdentity'] != null)
          'workspaceIdentity': relay.first['workspaceIdentity'],
      };
      // ignore: avoid_print
      print('PROBE scope: taskId=$taskId scope=$scope '
          '(live=${live.length} relay=${relay.length})');

      // --- baseline: bogus channel vs known channel ---
      await tryCall('zzz-bogus-channel', 'getAll');
      await tryCall('usage-stats', 'getAppUsageSnapshot');

      // --- A. zcode-task surface ---
      await tryCall('zcode-task', 'prepareWorkspace', [scope]);
      await tryCall('zcode-task', 'readPresentation', [scope]);
      await tryCall('zcode-task', 'getWorkspacePresentation', [scope]);
      if (taskId != null) {
        await tryCall('zcode-task', 'getTaskConfigOptions', [
          {'taskId': taskId, ...scope},
        ]);
        await tryCall('zcode-task', 'getTaskModelSelection', [
          {'taskId': taskId, ...scope},
        ]);
      }
      await tryCall('zcode-task', 'renameTask', [
        {...scope, 'taskId': 'bogus-task-id', 'title': 'probe'},
      ]);
      await tryCall('zcode-task', 'setTaskUnread', [
        {...scope, 'taskId': 'bogus-task-id', 'unread': true},
      ]);

      // --- B. automation surface (zcode-agent) ---
      await tryCall('zcode-agent', 'listAllAutomations');
      await tryCall('zcode-agent', 'listAutomations', [scope]);
      await tryCall('zcode-agent', 'setAutomationEnabled', [
        {...scope, 'automationId': 'bogus-automation-id', 'enabled': false},
      ]);
      await tryCall('zcode-agent', 'restartAutomation', [
        {...scope, 'automationId': 'bogus-automation-id'},
      ]);
      await tryCall('zcode-agent', 'listAutomationRuns', [
        {...scope, 'automationId': 'bogus-automation-id'},
      ]);

      // --- C. off-peak-task channel surface ---
      for (final m in [
        'list', 'listAll', 'listTasks', 'listOffPeakTasks', 'getStatus',
        'status', 'getQuota', 'run', 'createTask', 'pauseTask',
      ]) {
        await tryCall('off-peak-task', m);
      }

      // --- D. model-provider replacement channels ---
      for (final m in [
        'getAll', 'list', 'getProviders', 'getSettings', 'get', 'read',
        'getConfig', 'load',
      ]) {
        await tryCall('provider-settings', m);
      }
      for (final m in [
        'getAll', 'list', 'get', 'getOptions', 'getDefaults', 'options',
      ]) {
        await tryCall('model-selection', m);
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
