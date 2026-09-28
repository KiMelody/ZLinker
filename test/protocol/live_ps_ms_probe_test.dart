import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL, 09-28 new-task-defaults round): does the
/// 3.14.3 desktop expose `provider-settings` / `model-selection` to a
/// mobileApp-kind terminal, and what does getView return? `model-provider`
/// is the dead-channel baseline (must answer "Channel name … timed out").
/// Read-only: getView/refresh only, no CRUD.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings / model-selection exposure', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps', params: params);
    Future<void> tryCall(String channel, String method,
        [List<Object?> args = const []]) async {
      try {
        final res = await session.callChannel(channel, method, args);
        String brief;
        if (res is Map) {
          brief = 'keys=${res.keys.toList()}';
          final ps = res['providers'];
          if (ps is List) {
            brief += ' providers.len=${ps.length}';
            if (ps.isNotEmpty && ps.first is Map) {
              brief += ' provider0.keys=${(ps.first as Map).keys.toList()}';
            }
          }
          final pp = res['personalProviders'];
          if (pp is List) brief += ' personalProviders.len=${pp.length}';
        } else if (res is List) {
          brief = 'listLen=${res.length}';
        } else {
          brief = '$res';
        }
        // ignore: avoid_print
        print('PROBE $channel.$method OK $brief');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $channel.$method ERR $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      await tryCall('model-selection', 'getView');
      await tryCall('provider-settings', 'getView');
      await tryCall('provider-settings', 'refresh');
      // dead-channel baseline: must time out
      await tryCall('model-provider', 'getAll');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
