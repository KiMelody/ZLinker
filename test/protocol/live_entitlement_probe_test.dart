import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): dumps entitlement snapshot variants
/// (usage-stats.getEntitlementSnapshot) and the top-level keys of live
/// conversation snapshots (hunting for quota / planUsage-style pushes
/// beyond the manual usage-stats pull). Skipped without the env var.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live entitlement snapshot probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe5', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      const encoder = JsonEncoder.withIndent('  ');

      // Grab the provider id of the newest task's conversation config so the
      // entitlement call can be provider-scoped (bare calls may return
      // not_configured when several providers exist).
      String? providerId;
      final tasks = [
        for (final t in session.relayTasks)
          if ('${t['taskId']}'.isNotEmpty) '${t['taskId']}',
      ];
      for (final taskId in tasks.take(3)) {
        final handle = await session.subscribe(taskId);
        for (var i = 0; i < 10 && handle.state.snapshot == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final snap = handle.state.snapshot;
        // ignore: avoid_print
        print('PROBE task=$taskId snapshotKeys=${snap?.keys.toList()}');
        if (snap != null) {
          for (final k in ['planUsage', 'quota', 'entitlement', 'usage']) {
            if (snap[k] != null) {
              // ignore: avoid_print
              print('PROBE task=$taskId $k=${snap[k]}');
            }
          }
          providerId ??= (snap['config']
                  as Map?)?['provider'] as String?;
        }
        await handle.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      // ignore: avoid_print
      print('PROBE providerId=$providerId');

      // Entitlement variants: bare (what device_usage_page calls today) and
      // provider-scoped (web bundle signature has preferredProviderId).
      final variants = <Map<String, Object?>>[
        {'includeSubscription': true},
        if (providerId != null)
          {
            'includeSubscription': true,
            'preferredProviderId': providerId,
            'allowDisabledPreferredProvider': true,
            'requirePreferredProvider': false,
          },
      ];
      for (final v in variants) {
        try {
          final res =
              await session.callChannel('usage-stats', 'getEntitlementSnapshot', [v]);
          // ignore: avoid_print
          print('PROBE entitlement ${v.keys.toList()}=\n${encoder.convert(res)}');
        } catch (e) {
          // ignore: avoid_print
          print('PROBE entitlement ${v.keys.toList()} failed: $e');
        }
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
