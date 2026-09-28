import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live WRITE probe round 5 (09-28 providers-revival implement step 1b).
/// Round 4 hit "Provider Settings snapshot revision conflict" when
/// setPersonalModelEnabled ran right after two addPersonalModel calls
/// (the desktop-side guard asserts snapshot identity; a pending refresh
/// swaps the snapshot and the write aborts BEFORE landing — retry-safe).
/// This probe certifies the positive path: getView resync between writes,
/// then setPersonalModelEnabled(pid, modelId, false/true) arg order and
/// its view effect, on a disposable provider.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings setEnabled certification', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps-step1b', params: params);

    String trim(Object? o, [int max = 900]) {
      var s = const JsonEncoder.withIndent('  ').convert(o);
      if (s.length > max) s = '${s.substring(0, max)}…<trimmed ${s.length}>';
      return s;
    }

    Future<Object?> call(String method, List<Object?> args) async {
      try {
        final res = await session.callChannel('provider-settings', method,
            args);
        // ignore: avoid_print
        print('PROBE $method OK ${trim(res, 300)}');
        return res;
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $method ERR $e');
        return null;
      }
    }

    Map? entryOf(Object? view, String pid) {
      final ps = view is Map ? view['providers'] : null;
      if (ps is! List) return null;
      for (final p in ps) {
        if (p is Map && '${p['providerId']}' == pid) return p;
      }
      return null;
    }

    Object? modelOf(Object? view, String pid, String mid) {
      final models = entryOf(view, pid)?['models'];
      if (models is! List) return null;
      for (final m in models) {
        if (m is Map && '${m['modelId']}' == mid) return m;
      }
      return null;
    }

    Future<Object?> resync() => call('getView', const []);

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      final baseView = await resync();
      final baseCount = (baseView is Map ? baseView['providers'] as List : [])
          .length;

      final created = await call('createPersonalProvider',
          const [{'providerName': 'zl-probe-p5'}]);
      final pid = (created is Map ? created['providerId'] : null) as String?;
      // ignore: avoid_print
      print('PROBE pid=$pid');
      if (pid == null) throw StateError('no temp provider — aborting');

      try {
        await call('addPersonalModel', [pid, 'zl-probe-m5', const {}, true]);
        // resync between writes (round-4 contract)
        await resync();

        // setPersonalModelEnabled arg order (providerId, modelId, boolean)
        await call('setPersonalModelEnabled', [pid, 'zl-probe-m5', false]);
        var v = await resync();
        var m = modelOf(v, pid, 'zl-probe-m5');
        // ignore: avoid_print
        print('PROBE verify after-disable model=${trim(m)}');
        expect((m as Map?)?['enabled'], false,
            reason: 'model must be disabled');

        await resync();
        await call('setPersonalModelEnabled', [pid, 'zl-probe-m5', true]);
        v = await resync();
        m = modelOf(v, pid, 'zl-probe-m5');
        // ignore: avoid_print
        print('PROBE verify after-enable model=${trim(m)}');
        expect((m as Map?)?['enabled'], true,
            reason: 'model must be re-enabled');
      } finally {
        await call('deletePersonalProvider', [pid]);
        final finalView = await resync();
        final gone = entryOf(finalView, pid) == null;
        final count =
            (finalView is Map ? finalView['providers'] as List : []).length;
        // ignore: avoid_print
        print('PROBE cleanup gone=$gone countRestored=${count == baseCount}');
        expect(gone, true, reason: 'temp provider must be deleted');
        expect(count, baseCount, reason: 'provider count must be restored');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
