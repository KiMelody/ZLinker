import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/protocol/remote_client.dart';
import 'package:zlinker/state/device_session.dart';

/// Live read-only probe for the coding-plan quota-reset opportunity service
/// (ZLINKER_PROBE_URL): which channel exposes getCodingPlanResetStatus and
/// what the status snapshot looks like. Read-only — the mutating methods
/// (requestCodingPlanResetOpportunity / useCodingPlanReset /
/// markCodingPlanResetHistoryRead) are intentionally never called.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live quota reset opportunity probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(
      deviceId: 'probe-reset',
      params: params,
      clientFactory: () => RemoteClient(params),
    );
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // Read-only status query against both candidate channels.
      for (final channel in ['coding-plan-subscription', 'usage-stats']) {
        try {
          final res = await session.callChannel(
              channel, 'getCodingPlanResetStatus', [const <String, dynamic>{}]);
          // ignore: avoid_print
          print('PROBE $channel getCodingPlanResetStatus => OK');
          _dump(res);
        } catch (e) {
          // ignore: avoid_print
          print('PROBE $channel getCodingPlanResetStatus => FAIL: $e');
        }
      }

      // Entitlement snapshot for cross-reference (expected not_configured
      // on this desktop, but re-confirm).
      try {
        final ent = await session.callChannel('usage-stats',
            'getEntitlementSnapshot', [
          const {'includeSubscription': true}
        ]);
        // ignore: avoid_print
        print('PROBE entitlement keys => '
            '${ent is Map ? ent.keys.toList() : ent.runtimeType}');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE entitlement => FAIL: $e');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

void _dump(Object? res, [int depth = 0]) {
  final pad = '  ' * depth;
  if (res is Map) {
    // ignore: avoid_print
    print('$pad${res.keys.toList()}');
    if (depth < 3) {
      for (final entry in res.entries.take(12)) {
        // ignore: avoid_print
        print('$pad${entry.key}:');
        _dump(entry.value, depth + 1);
      }
    }
  } else if (res is List) {
    // ignore: avoid_print
    print('${pad}list(${res.length})');
    if (depth < 3) {
      for (final item in res.take(3)) {
        _dump(item, depth + 1);
      }
    }
  } else {
    // ignore: avoid_print
    print('$pad$res');
  }
}
