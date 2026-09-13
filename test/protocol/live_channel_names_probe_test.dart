import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): channel-name discovery for the
/// model-provider regressions — a bogus channel gives the desktop's
/// "unknown channel" error baseline, then candidate names are tried
/// with getAll until one answers.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live channel-name probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe7', params: params);
    Future<void> tryChannel(String channel, String method) async {
      try {
        final res = await session.callChannel(channel, method, const []);
        // ignore: avoid_print
        print('PROBE $channel.$method OK '
            '${res is Map ? 'keys=${res.keys.take(8).toList()}' : res is List ? 'listLen=${res.length}' : res.runtimeType}');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $channel.$method ERR $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // baseline: how the desktop answers a channel that certainly
      // doesn't exist, vs one that exists (usage-stats answered today)
      await tryChannel('zzz-bogus-channel', 'getAll');
      await tryChannel('usage-stats', 'getAppUsageSnapshot');

      // model-provider candidates (camelCase / plural / registry variants)
      for (final c in [
        'model-provider',
        'modelProvider',
        'model-providers',
        'model-provider-registry',
        'provider',
        'providers',
      ]) {
        await tryChannel(c, 'getAll');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
