import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live WRITE probe (ZLINKER_PROBE_URL, 09-28 providers-revival research,
/// user-approved decision #3): one disposable provider `zl-probe-temp` is
/// created, save/add-model/rename shapes are probed (errors are evidence),
/// then deleted and the deletion verified. Never touches existing providers;
/// reorderPersonalProviders is NOT probed (it mutates the global order).
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings CRUD shapes', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps-crud', params: params);

    String trim(Object? o, [int max = 700]) {
      var s = const JsonEncoder.withIndent('  ').convert(o);
      if (s.length > max) s = '${s.substring(0, max)}…<trimmed ${s.length}>';
      return s;
    }

    Future<Object?> call(String method, List<Object?> args) async {
      try {
        final res = await session.callChannel(
            'provider-settings', method, args);
        // ignore: avoid_print
        print('PROBE $method OK ${trim(res)}');
        return res;
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $method ERR $e');
        return null;
      }
    }

    Object? dig(Object? o, List<String> path) {
      var cur = o;
      for (final k in path) {
        if (cur is! Map) return null;
        cur = cur[k];
      }
      return cur;
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // 0) baseline view + template entry shape (endpoint-preset evidence)
      final base = await call('getView', const []);
      final baseProviders = dig(base, const ['providers']);
      final baseCount =
          baseProviders is List ? baseProviders.length : 'unknown';
      // ignore: avoid_print
      print('PROBE baseline providers=$baseCount revision='
          '${dig(base, const ['revision'])}');
      final templates = dig(base, const ['providerTemplates']);
      if (templates is List && templates.isNotEmpty) {
        // ignore: avoid_print
        print('PROBE template0=${trim(templates.first, 900)}');
      }

      // 1) create the disposable provider
      final created =
          await call('createPersonalProvider', const [
            {'providerName': 'zl-probe-temp'}
          ]);
      var pid = dig(created, const ['providerId']) as String?;
      pid ??= dig(created, const ['result', 'providerId']) as String?;
      if (pid == null) {
        // last resort: locate by name in the returned/refreshed view
        final view = dig(created, const ['view']) ??
            dig(created, const ['result', 'view']) ??
            (await call('getView', const []));
        final ps = dig(view, const ['providers']);
        if (ps is List) {
          for (final p in ps.reversed) {
            if (p is Map && '${p['providerName']}' == 'zl-probe-temp') {
              pid = '${p['providerId']}';
              break;
            }
          }
        }
      }
      // ignore: avoid_print
      print('PROBE resolved providerId=$pid');
      if (pid == null) {
        throw StateError('could not resolve providerId — aborting writes');
      }

      // 2) savePersonalProviderOverlay shape probing
      await call('savePersonalProviderOverlay', [
        pid,
        {'providerName': 'zl-probe-temp-renamed'}
      ]);
      await call('savePersonalProviderOverlay', [
        pid,
        {'providerName': 'zl-probe-temp-renamed'},
        dig(created, const ['revision']) ?? dig(base, const ['revision']),
      ]);

      // 3) per-model management on the temp provider only
      await call('addPersonalModel', [pid, {'modelId': 'zl-probe-model'}]);
      await call('addPersonalModel', [pid, 'zl-probe-model']);
      await call('renamePersonalModel',
          [pid, 'zl-probe-model', {'modelId': 'zl-probe-model-2'}]);
      await call(
          'renamePersonalModel', [pid, 'zl-probe-model', 'zl-probe-model-2']);

      // 4) verify the writes landed, then clean up
      final after = await call('getView', const []);
      final aps = dig(after, const ['providers']);
      Map? tempEntry;
      if (aps is List) {
        for (final p in aps) {
          if (p is Map && '${p['providerId']}' == pid) tempEntry = p;
        }
      }
      // ignore: avoid_print
      print('PROBE tempEntryAfterWrites=${trim(tempEntry, 900)}');
      await call('deletePersonalProvider', [pid]);
      final final_ = await call('getView', const []);
      final fps = dig(final_, const ['providers']);
      final gone = fps is List &&
          !fps.any((p) => p is Map && '${p['providerId']}' == pid);
      // ignore: avoid_print
      print('PROBE cleanup verified gone=$gone '
          'finalCount=${fps is List ? fps.length : 'unknown'}');
      expect(gone, true, reason: 'temp provider must be deleted');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
