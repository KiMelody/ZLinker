import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live WRITE probe round 4 (09-28 providers-revival implement step 1).
/// Certifies the remaining wire shapes against the live desktop:
///  - setPersonalModelEnabled arg order (providerId, modelId, bool)
///  - deletePersonalModel(providerId, modelId)
///  - reorderPersonalModels(providerId, [modelId]) and
///    reorderPersonalProviders([providerId]) — reorderPersonalProviders is
///    exercised ONLY with the two disposable temp providers created here,
///    never with the user's real providers.
///  - whether savePersonalProviderOverlay / addPersonalModel land on a
///    built-in (non-personal, non-account) providerId — tested with a
///    semantic no-op (empty overlay + `rulePatch{enabled:<current>}`) so a
///    success leaves no state change; an added probe model is deleted again.
/// Cleanup deletes both zl-probe-* providers and asserts the provider count
/// matches the baseline. Read paths print ids/groups/enabled only — no
/// secrets, and no user provider names beyond the id list shape.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live provider-settings step-1 certification', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-ps-step1', params: params);

    String trim(Object? o, [int max = 700]) {
      var s = const JsonEncoder.withIndent('  ').convert(o);
      if (s.length > max) s = '${s.substring(0, max)}…<trimmed ${s.length}>';
      return s;
    }

    Future<Object?> call(String method, List<Object?> args) async {
      try {
        final res = await session.callChannel('provider-settings', method,
            args);
        // ignore: avoid_print
        print('PROBE $method OK ${trim(res)}');
        return res;
      } catch (e) {
        // ignore: avoid_print
        print('PROBE $method ERR $e');
        return null;
      }
    }

    List<Map> providerListOf(Object? view) {
      final ps = view is Map ? view['providers'] : null;
      return ps is List ? ps.whereType<Map>().toList() : const [];
    }

    Map? entryOf(Object? view, String pid) => providerListOf(view)
        .where((p) => '${p['providerId']}' == pid)
        .toList()
        .firstOrNull;

    void dump(Object? view, String tag) {
      final order = view is Map ? view['providerOrder'] : null;
      // ignore: avoid_print
      print('VIEW[$tag] revision=${view is Map ? view['revision'] : '?'} '
          'count=${providerListOf(view).length} order=$order');
      for (final p in providerListOf(view)) {
        final pc = p['personalConfig'];
        final eff = p['effectiveConfig'];
        final builtin = p['effectiveBuiltinConfig'];
        String groupOf(Object? cfg) =>
            cfg is Map ? '${cfg['group']}' : 'null';
        // ignore: avoid_print
        print('VIEW[$tag] id=${p['providerId']} '
            'templateId=${p['templateId']} enabled=${p['enabled']} '
            'executable=${p['executable']} '
            'accountState=${p['accountState'] != null} '
            'pcGroup=${groupOf(pc)} effGroup=${groupOf(eff)} '
            'builtinCfgGroup=${groupOf(builtin)} '
            'models=${(p['models'] as List?)?.length}');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      final baseView = await call('getView', const []);
      dump(baseView, 'baseline');
      final baseCount = providerListOf(baseView).length;

      // --- pick a built-in (non-personal, non-account) target -------------
      final builtin = providerListOf(baseView).firstWhere(
        (p) =>
            p['personalConfig'] == null &&
            p['accountState'] == null &&
            p['enabled'] == false &&
            '${p['providerId']}'.startsWith('zcode-builtin'),
        orElse: () => const {},
      );
      final builtinPid = builtin.isEmpty ? null : '${builtin['providerId']}';
      // ignore: avoid_print
      print('PROBE builtinTarget=$builtinPid');

      // --- two disposable temp providers ----------------------------------
      final created1 = await call('createPersonalProvider',
          const [{'providerName': 'zl-probe-p1'}]);
      final pid1 = (created1 is Map ? created1['providerId'] : null) as String?;
      final created2 = await call('createPersonalProvider',
          const [{'providerName': 'zl-probe-p2'}]);
      final pid2 = (created2 is Map ? created2['providerId'] : null) as String?;
      // ignore: avoid_print
      print('PROBE pids=$pid1,$pid2');
      if (pid1 == null || pid2 == null) {
        throw StateError('temp providers missing — aborting writes');
      }

      try {
        // --- model ops on pid1 --------------------------------------------
        await call('addPersonalModel', [pid1, 'zl-probe-m-a', const {}, true]);
        await call('addPersonalModel', [pid1, 'zl-probe-m-b', const {}, true]);

        // setPersonalModelEnabled arg order candidate A: (pid, modelId, bool)
        final setEnabled = await call(
            'setPersonalModelEnabled', [pid1, 'zl-probe-m-a', false]);
        final afterDisable = await call('getView', const []);
        final m = entryOf(afterDisable, pid1)?['models'] as List?;
        final a = m
            ?.whereType<Map>()
            .where((x) => '${x['modelId']}' == 'zl-probe-m-a')
            .toList()
            .firstOrNull;
        // ignore: avoid_print
        print('PROBE verify setEnabled(argOrderA) res=${setEnabled != null} '
            'modelA.enabled=${a?['enabled']}');

        // reorderPersonalModels(pid, [ids]) — b before a
        await call('reorderPersonalModels',
            [pid1, const ['zl-probe-m-b', 'zl-probe-m-a']]);
        final afterReorder = await call('getView', const []);
        final pc1 = entryOf(afterReorder, pid1)?['personalConfig'];
        // ignore: avoid_print
        print('PROBE verify reorderModels personalConfig=${trim(pc1)}');

        // deletePersonalModel(pid, modelId)
        await call('deletePersonalModel', [pid1, 'zl-probe-m-b']);
        final afterDelete = await call('getView', const []);
        final ids = ((entryOf(afterDelete, pid1)?['personalConfig'] as Map?)
                    ?['personalModelIds'] as List? ??
                const [])
            .map((e) => '$e')
            .toList();
        // ignore: avoid_print
        print('PROBE verify deleteModel personalModelIds=$ids');

        // --- reorderPersonalProviders([pid2, pid1]) — temps only ----------
        await call('reorderPersonalProviders', [
          [pid2, pid1]
        ]);
        final afterProviderReorder = await call('getView', const []);
        // ignore: avoid_print
        print('PROBE verify reorderProviders '
            'order=${afterProviderReorder is Map ? afterProviderReorder['providerOrder'] : '?'}');

        // --- built-in target: overlay + addModel legality (no-op forms) ---
        if (builtinPid != null) {
          final curEnabled = builtin['enabled'] == true;
          await call('savePersonalProviderOverlay', [
            builtinPid,
            const <String, Object>{},
            {'enabled': curEnabled},
          ]);
          await call('addPersonalModel',
              [builtinPid, 'zl-probe-m-x', const {}, true]);
          final afterBuiltin = await call('getView', const []);
          final bx = entryOf(afterBuiltin, builtinPid);
          final pcB = bx?['personalConfig'];
          // ignore: avoid_print
          print('PROBE verify builtin after=${trim(pcB)}');
          await call('deletePersonalModel', [builtinPid, 'zl-probe-m-x']);
          final afterBuiltin2 = await call('getView', const []);
          // ignore: avoid_print
          print('PROBE verify builtin after-cleanup '
              'pc=${trim(entryOf(afterBuiltin2, builtinPid)?['personalConfig'])}');
        }
      } finally {
        // --- cleanup --------------------------------------------------------
        await call('deletePersonalProvider', [pid1]);
        await call('deletePersonalProvider', [pid2]);
        final finalView = await call('getView', const []);
        dump(finalView, 'final');
        final gone = entryOf(finalView, pid1) == null &&
            entryOf(finalView, pid2) == null;
        final countOk = providerListOf(finalView).length == baseCount;
        // ignore: avoid_print
        print('PROBE cleanup gone=$gone countRestored=$countOk');
        expect(gone, true, reason: 'temp providers must be deleted');
        expect(countOk, true, reason: 'provider count must be restored');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
