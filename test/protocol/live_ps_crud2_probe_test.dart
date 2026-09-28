import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live WRITE probe round 2 (ZLINKER_PROBE_URL, 09-28 providers-revival):
/// with the statically-derived wire shapes — savePersonalProviderOverlay
/// (providerId, overlay{api…}, rulePatch{providerName…}) and
/// addPersonalModel (providerId, modelId, modelConfig, useRecommendedConfig)
/// — land real writes on a disposable provider, then delete it. Also
/// presence-checks testModelConnectivity / resolveModelConfig (validation
/// error ⇒ method exists remotely; Method-not-found ⇒ absent).
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings CRUD round 2', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps-crud2', params: params);

    String trim(Object? o, [int max = 800]) {
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

    Map? entryOf(Object? view, String pid) {
      final ps = view is Map ? view['providers'] : null;
      if (ps is! List) return null;
      for (final p in ps) {
        if (p is Map && '${p['providerId']}' == pid) return p;
      }
      return null;
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      final created = await call('createPersonalProvider', const [
        {'providerName': 'zl-probe-temp2'}
      ]);
      final pid = (dig(created, const ['providerId']) ??
              dig(created, const ['result', 'providerId'])) as String?;
      // ignore: avoid_print
      print('PROBE pid=$pid');
      if (pid == null) throw StateError('no providerId — aborting writes');

      // 1) save: overlay{api.baseUrl} + rulePatch{providerName} (static shape)
      await call('savePersonalProviderOverlay', [
        pid,
        {
          'api': {
            'type': 'anthropic-messages',
            'baseUrl': 'https://example.invalid',
          },
        },
        {'providerName': 'zl-probe-temp2-renamed'},
      ]);
      // minimal variant: rulePatch only (empty overlay)
      await call('savePersonalProviderOverlay', [
        pid,
        <String, Object>{},
        {'providerName': 'zl-probe-temp2-renamed'},
      ]);

      // 2) addPersonalModel(providerId, modelId, modelConfig, useRecommended)
      await call('addPersonalModel', [pid, 'zl-probe-model', const {}, true]);
      // 3) rename now that the model should exist
      await call(
          'renamePersonalModel', [pid, 'zl-probe-model', 'zl-probe-model-2']);

      // 4) presence checks (host-side capability question)
      await call('resolveModelConfig', [
        {'providerId': pid, 'modelId': 'zl-probe-model-2'}
      ]);
      await call('testModelConnectivity', [
        {'providerId': pid, 'modelId': 'zl-probe-model-2'}
      ]);

      // 5) verify writes landed, then clean up
      final after = await call('getView', const []);
      final entry = entryOf(after, pid);
      // ignore: avoid_print
      print('PROBE finalEntry=${trim(entry, 1000)}');
      await call('deletePersonalProvider', [pid]);
      final finalView = await call('getView', const []);
      final gone = entryOf(finalView, pid) == null;
      // ignore: avoid_print
      print('PROBE cleanup gone=$gone');
      expect(gone, true, reason: 'temp provider must be deleted');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
