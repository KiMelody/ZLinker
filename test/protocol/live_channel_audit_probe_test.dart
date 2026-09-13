import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): channel-exposure audit. A channel that
/// exists answers with data or an arg/method error; one that isn't exposed
/// answers "Channel name '…' timed out". Maps which channels the current
/// desktop still exposes to remote terminals.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live channel exposure audit', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe8', params: params);
    Future<void> tryCall(String channel, String method,
        [List<Object?> args = const []]) async {
      try {
        final res = await session.callChannel(channel, method, args);
        // ignore: avoid_print
        print('PROBE $channel.$method OK '
            '${res is Map ? 'keys=${res.keys.take(10).toList()}' : res is List ? 'listLen=${res.length}' : res}');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $channel.$method ERR $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // channels the app uses today
      await tryCall('subagents', 'list');
      await tryCall('file', 'listWorkspaceFiles', [
        {'rootPath': 'F:\\ZLinker'}
      ]);
      await tryCall('skills', 'list', [
        {'workspacePath': 'F:\\ZLinker'}
      ]);
      await tryCall('zcode-agent', 'listAllAutomations');
      await tryCall('zcode-task', 'list');
      await tryCall('off-peak-task', 'list');
      await tryCall('usage-stats', 'getEntitlementSnapshot', [
        {'includeSubscription': true}
      ]);

      // candidate new homes for provider / plan data
      await tryCall('model-provider', 'getAll');
      await tryCall('coding-plan-subscription', 'getSnapshot');
      await tryCall('coding-plan-subscription', 'getCurrent');
      await tryCall('settings', 'get');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
