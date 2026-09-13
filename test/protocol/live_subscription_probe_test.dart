import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): method-name discovery on the
/// coding-plan-subscription channel (channel is registered on the current
/// desktop; only the method names are unknown). Follows the repo's
/// try-until-accepted probing discipline.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live coding-plan-subscription method probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe9', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      const candidates = [
        'get',
        'getSubscription',
        'getCurrent',
        'getStatus',
        'getSnapshot',
        'getCurrentSubscription',
        'getActiveSubscription',
        'getPlan',
        'getCodingPlan',
        'getEntitlement',
        'getUsage',
        'list',
      ];
      for (final m in candidates) {
        try {
          final res = await session
              .callChannel('coding-plan-subscription', m, const []);
          // ignore: avoid_print
          print('PROBE HIT $m -> $res');
        } catch (e) {
          // ignore: avoid_print
          print('PROBE miss $m: $e');
        }
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
