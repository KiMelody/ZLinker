import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';
import 'package:zlinker/state/entitlement_poller.dart';

/// Live probe (ZLINKER_PROBE_URL): 3.12.3 coding-plan quota data sources.
/// Compares the entitlement snapshot paths and the direct coding-plan usage
/// snapshot to design the 5h-quota fallback. The second test walks the
/// production chain (session.entitlementSnapshot → _resolvePlanAccess →
/// full-param call) end to end.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live quota source probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123d', params: params);

    Future<Map<String, dynamic>?> tryCall(String method,
        [List<Object?> args = const []]) async {
      try {
        final res = await session.callChannel('usage-stats', method, args);
        if (res is Map) {
          // ignore: avoid_print
          print('PROBE HIT  $method -> keys=${res.keys.toList()}');
          return res.cast<String, dynamic>();
        }
        // ignore: avoid_print
        print('PROBE HIT  $method -> ${res.runtimeType}');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE miss $method: $e');
      }
      return null;
    }

    void dumpQuota(Map<String, dynamic> m, String tag) {
      final quota = m['quota'];
      if (quota is Map && quota['limits'] is List) {
        for (final l in (quota['limits'] as List).whereType<Map>()) {
          // ignore: avoid_print
          print('PROBE $tag limit: type=${l['type']} unit=${l['unit']} '
              'number=${l['number']} pct=${l['percentage']} '
              'nextReset=${l['nextResetTime']}');
        }
      } else {
        // ignore: avoid_print
        print('PROBE $tag quota=$quota');
      }
      // ignore: avoid_print
      print('PROBE $tag provider=${m['provider']} '
          'authenticated=${m['authenticated']} '
          'unavailableReason=${m['unavailableReason']} '
          'remaining=${m['remaining']} sub=${m['subscription']}');
    }

    const plan = 'account:zai-individual-coding-plan';
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // 1. ZLinker's current call shape.
      final a = await tryCall('getEntitlementSnapshot', [
        {'includeSubscription': true},
      ]);
      if (a != null) {
        dumpQuota(a, 'entitlement-bare');
        // ignore: avoid_print
        print('PROBE entitlement-bare context=${a['context']}');
      }

      // 2. Official desktop call shape (family enum: zai|bigmodel).
      final b = await tryCall('getEntitlementSnapshot', [
        {
          'includeSubscription': true,
          'preferredProviderId': plan,
          'accountAccess': {
            'type': 'zhipu-account',
            'family': 'zai',
            'planKind': 'individual-coding-plan',
          },
          'allowDisabledPreferredProvider': true,
          'requirePreferredProvider': true,
          'allowEnvApiKey': false,
        },
      ]);
      if (b != null) dumpQuota(b, 'entitlement-full');

      // 3. The direct coding-plan usage snapshot with accountAccess.
      final c = await tryCall('getCodingPlanUsageSnapshot', [
        {
          'preferredProviderId': plan,
          'accountAccess': {
            'type': 'zhipu-account',
            'family': 'individual',
            'planKind': 'individual-coding-plan',
          },
          'allowEnvApiKey': false,
        },
      ]);
      if (c != null) {
        // ignore: avoid_print
        print('PROBE codingPlanUsage full: $c');
      }

      // 4. Env-API-key fallback variant + reset status side-effect check.
      final e2 = await tryCall('getEntitlementSnapshot', [
        {
          'includeSubscription': true,
          'preferredProviderId': plan,
          'allowEnvApiKey': true,
        },
      ]);
      if (e2 != null) dumpQuota(e2, 'entitlement-envkey');
      await tryCall('getCodingPlanUsageSnapshot', [
        {
          'preferredProviderId': plan,
          'accountAccess': {
            'type': 'zhipu-account',
            'family': 'zai',
            'planKind': 'individual-coding-plan',
          },
        },
      ]);
      await tryCall('getCodingPlanResetStatus', [
        {'preferredProviderId': plan},
      ]);

      // 5. coding-plan-subscription channel surface.
      for (final m in [
        'get', 'getSubscription', 'getCurrent', 'getStatus', 'getSnapshot',
        'getEntitlement', 'getUsage', 'list',
      ]) {
        try {
          final res = await session
              .callChannel('coding-plan-subscription', m, const []);
          // ignore: avoid_print
          print('PROBE HIT  cps.$m -> '
              '${res is Map ? 'keys=${res.keys.toList()}' : res}');
        } catch (err) {
          // ignore: avoid_print
          print('PROBE miss cps.$m: $err');
        }
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live entitlement via production chain', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123e', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // Walks the shipped path: version gate → plan derivation
      // (getTaskModelSelection) → full-param getEntitlementSnapshot.
      final view = await session.entitlementSnapshot();
      // ignore: avoid_print
      print('PROBE session entitlement phase=${view.phase.name} '
          'provider=${view.data?['provider']} '
          'unavailable=${view.data?['unavailableReason']}');
      final fiveHour = view.limitFor('TIME_LIMIT');
      final week = view.limitFor('TOKENS_LIMIT');
      // ignore: avoid_print
      print('PROBE session 5h pct=${fiveHour?.percentage} '
          'next=${fiveHour?.nextResetTime} | '
          'week pct=${week?.percentage} next=${week?.nextResetTime}');
      expect(view.phase, EntitlementPhase.ok,
          reason: 'production chain should hit the full-param snapshot');

      // Reset-status chain with the injected accountAccess: the response
      // must no longer be account_access_required.
      final reset = await session.quotaResetStatus();
      // ignore: avoid_print
      print('PROBE session resetStatus -> $reset');
      expect('$reset', isNot(contains('account_access_required')));
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
