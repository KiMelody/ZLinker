import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Read-only acceptance probe: dump the zl-acce* test provider's current
/// models + view revision straight from the desktop, so the emulator-side
/// UI verdicts can be cross-checked against the wire truth.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live zlacce2e provider state', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-zl-accept', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      final res = await session
          .callChannel('provider-settings', 'getView', const <Object?>[]);
      final view = res as Map;
      // ignore: avoid_print
      print('VIEW revision=${view['revision']}');
      final providers = view['providers'] as List;
      for (final p0 in providers) {
        final p = p0 as Map;
        if ('${p['providerName']}'.startsWith('zl')) {
          final models = p['models'];
          final ids = models is List
              ? [
                  for (final m in models)
                    '${(m as Map)['modelId']}'
                        '(enabled=${m['enabled']},rec=${m['useRecommendedConfig']})'
                ]
              : '$models';
          // ignore: avoid_print
          print('ZLPROV ${p['providerId']} | ${p['providerName']} | '
              'order=[${view['providerOrder']}]');
          // ignore: avoid_print
          print('  models=$ids');
        }
      }
    } finally {
      await session.dispose();
    }
  });
}
