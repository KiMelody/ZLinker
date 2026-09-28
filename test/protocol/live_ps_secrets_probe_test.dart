import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (09-28 providers-revival round): does `provider-settings.getView`
/// carry provider API keys on the wire? The official web remote prefills the
/// masked key input with a real value (sk-…, 67 chars), so SOME source
/// exposes it. This probe dumps each provider's personalConfig.access /
/// effectiveConfig.access (values truncated to prefix+length) to see whether
/// getView is that source or a separate credential RPC exists.
/// Read-only: getView only.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings key exposure', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps-sec', params: params);
    String briefValue(Object? v) {
      if (v is String) {
        return v.length > 12 ? '${v.substring(0, 6)}…(len=${v.length})' : v;
      }
      return '$v';
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      final res = await session
          .callChannel('provider-settings', 'getView', const <Object?>[]);
      final providers = (res as Map)['providers'] as List;
      for (final p0 in providers) {
        final p = p0 as Map;
        final pc = (p['personalConfig'] as Map?) ?? const {};
        final eff = (p['effectiveConfig'] as Map?) ?? const {};
        final pcAcc = pc['access'];
        final effAcc = eff['access'];
        String accStr(Object? acc) {
          if (acc is! Map) return 'null';
          return acc.keys.map((k) => '$k=${briefValue(acc[k])}').join(', ');
        }
        // ignore: avoid_print
        print(
          'PROV ${p['providerId']} | ${p['providerName']} | executable=${p['executable']}\n'
          '  personalConfig.keys=${pc.keys.toList()}\n'
          '  personal.access={${accStr(pcAcc)}}\n'
          '  effective.keys=${eff.keys.toList()}\n'
          '  effective.access={${accStr(effAcc)}}',
        );
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
