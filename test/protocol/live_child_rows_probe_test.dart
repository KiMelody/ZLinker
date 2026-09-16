import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): do CHILD tool-call rows exist in the
/// PARENT's conversation row space? The official web nests childToolCalls
/// under the Agent toolCall node, grouped client-side by assistantResponseId
/// (bundle archaeology 2026-09-16). The desktop session LOG has no child
/// tool parts — but the relay row space may still carry them. Dumps every
/// distinct (kind, toolName) in the parent window + history pages, and any
/// row sharing the Agent row's assistantResponseId.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live parent child-rows probe', () async {
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
      final parent = '${session.relayTasks.firstOrNull?['taskId'] ?? ''}';
      // ignore: avoid_print
      print('PROBE parent=$parent');
      if (parent.isEmpty) return;

      final handle = await session.subscribe(parent);
      for (var i = 0; i < 40 && !handle.state.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final state = handle.state;
      // ignore: avoid_print
      print('PROBE ready=${state.ready} window=${state.rows.length} '
          'firstRowId=${state.firstRowId} last=${state.rows.lastOrNull?['rowId']}');

      final all = <Map<String, dynamic>>[...state.rows];
      // Page back a few pages for a wider sample (firstRowId can be a
      // placeholder; derive the cursor from the actual window rows).
      final windowIds = state.rows
          .map((e) => (e['rowId'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      var before = windowIds.isEmpty ? 0 : windowIds.reduce((a, b) => a < b ? a : b);
      for (var page = 0; page < 4 && before > 1; page++) {
        final res = await session.callChannel(
            'zcode-agent', 'conversationRowsRangeV4', [
          {...session.offPeakScope, 'sessionId': parent, 'limit': 60, 'beforeRowId': before}
        ]);
        final ro = res is Map ? res['rows'] : null;
        List? rows = ro is Map ? ro['window'] as List? ?? ro['rows'] as List? : ro as List?;
        if (rows == null || rows.isEmpty) break;
        final mapped = rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        all.addAll(mapped);
        final ids = mapped.map((e) => (e['rowId'] as num?)?.toInt()).whereType<int>().toList();
        if (ids.isEmpty) break;
        final minId = ids.reduce((a, b) => a < b ? a : b);
        if (minId == before) break;
        before = minId;
      }

      // Distinct kind/toolName inventory + agent-response grouping.
      final inventory = <String, int>{};
      final agentRespIds = <String>{};
      for (final r in all) {
        final kind = '${r['kind']}';
        final tool = '${r['toolName'] ?? ''}';
        final key = kind == 'toolCall' ? 'toolCall/$tool' : kind;
        inventory[key] = (inventory[key] ?? 0) + 1;
        final ar = '${r['assistantResponseId'] ?? ''}';
        if (kind == 'toolCall' && tool.toLowerCase() == 'agent' && ar.isNotEmpty) {
          agentRespIds.add(ar);
        }
      }
      // ignore: avoid_print
      print('PROBE inventory=$inventory');
      // ignore: avoid_print
      print('PROBE agentResponseIds=$agentRespIds');
      final subRows = all.where((r) => r['kind'] == 'subagent').toList();
      // ignore: avoid_print
      print('PROBE subagentRows=${subRows.length} '
          'parentToolCallIds=${subRows.map((r) => '${r['parentToolCallId']}').toSet().take(5)}');

      // Any NON-Agent tool row sharing an Agent row's assistantResponseId
      // would be a child call nested in the parent row space.
      var nested = 0;
      for (final r in all) {
        if (r['kind'] != 'toolCall') continue;
        final ar = '${r['assistantResponseId'] ?? ''}';
        if (ar.isEmpty) continue;
        if ('${r['toolName'] ?? ''}'.toLowerCase() == 'agent') continue;
        if (agentRespIds.contains(ar)) {
          nested++;
          if (nested <= 5) {
            // ignore: avoid_print
            print('PROBE NESTED rowId=${r['rowId']} tool=${r['toolName']} '
                'ar=${ar.substring(0, ar.length > 18 ? 18 : ar.length)}… '
                'input=${'${r['inputText'] ?? ''}'.substring(0, '${r['inputText'] ?? ''}'.length > 80 ? 80 : '${r['inputText'] ?? ''}'.length)}');
          }
        }
      }
      // ignore: avoid_print
      print('PROBE nestedChildToolRows=$nested (sampled ${all.length} rows)');

      await handle.close();
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
