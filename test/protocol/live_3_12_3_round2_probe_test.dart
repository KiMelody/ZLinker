import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe round 2 (ZLINKER_PROBE_URL): follow-up to the 3.12.3 drift
/// round — provider-settings / model-selection method discovery with a wide
/// candidate net, off-peak-task arg-shape discovery, usage-stats sanity with
/// the app's real arg shape.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live 3.12.3 drift probe round 2', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123b', params: params);

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
        print('PROBE HIT  $channel.$method($args) -> $brief');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE miss $channel.$method($args): $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // --- usage-stats sanity: the app's real arg shape ---
      await tryCall('usage-stats', 'getAppUsageSnapshot', [
        {'range': '7d', 'timeZone': 'Asia/Shanghai'},
      ]);

      // --- provider-settings wide discovery ---
      for (final m in [
        'readAll', 'readProviders', 'getProvidersConfig',
        'getProviderSettings', 'listAll', 'getModels', 'readConfig',
        'snapshot', 'getSnapshot', 'readRegistry', 'getRegistry',
        'providers', 'getProviderList', 'fetchProviders', 'getAllProviders',
        'loadProviders', 'listProviderSettings', 'getProviderRegistry',
        'getRegistrySnapshot', 'readState', 'getState',
      ]) {
        await tryCall('provider-settings', m);
      }

      // --- model-selection wide discovery ---
      for (final m in [
        'readAll', 'getModels', 'listModels', 'getAvailableModels',
        'getSelection', 'getCurrent', 'read', 'getDefaults',
        'getConfiguredDefault', 'getDefaultSelection', 'snapshot',
      ]) {
        await tryCall('model-selection', m);
      }

      // --- off-peak-task arg shapes ---
      await tryCall('off-peak-task', 'pauseTask', ['bogus-id']);
      await tryCall('off-peak-task', 'pauseTask', [
        {'taskId': 'bogus-id'},
      ]);
      await tryCall('off-peak-task', 'continueTask', ['bogus-id']);
      await tryCall('off-peak-task', 'cancelTask', ['bogus-id']);
      await tryCall('off-peak-task', 'deleteTask', ['bogus-id']);
      await tryCall('off-peak-task', 'deleteHistory', ['bogus-id']);
      await tryCall('off-peak-task', 'updateTask', [
        'bogus-id',
        {'title': 'x'},
      ]);
      await tryCall('off-peak-task', 'createTask', [
        {'title': 'probe'},
      ]);
      await tryCall('off-peak-task', 'list');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
