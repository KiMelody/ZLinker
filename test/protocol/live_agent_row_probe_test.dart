import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL) for the subagent display gaps (09-16):
///
/// A. Parent-stream Agent toolCall row shape (what toolRowSemantics receives):
///    dump full JSON of toolName~/agent|task/ rows — live window plus a few
///    pages of conversationRowsRangeV4 history — to learn inputText keys and
///    whether outputText carries agentId / result text / childSessionId.
/// B. `kind=='subagent'` rows + snapshot.subagents + backgroundWorks while a
///    subagent runs; watch summaryText streaming cadence for ~30s.
/// C. Child-session subscribe: the fresh running child first (small), then
///    one older large child — the detail page's bridge-kill repro. Time each
///    to ready, then verify whether later RPCs still work (bridge alive?),
///    and cross-check conversationRowsRangeV4 as a fallback data source.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live agent-row + child-subscribe probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe9', params: params);

    String cut(Object? v, [int n = 400]) {
      var s = '$v';
      if (s.length > n) s = '${s.substring(0, n)}…(${s.length})';
      return s;
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // ---- pick the running parent session -------------------------------
      String? parent;
      for (final t in session.relayTasks.take(20)) {
        final phase = '${t['phase'] ?? t['status'] ?? ''}';
        final tid = '${t['taskId'] ?? ''}';
        if (tid.isNotEmpty && phase.contains('run')) {
          parent = tid;
          break;
        }
      }
      parent ??= '${session.relayTasks.firstOrNull?['taskId'] ?? ''}';
      // ignore: avoid_print
      print('PROBE parent=$parent');
      if (parent.isEmpty) return;

      final parentHandle = await session.subscribe(parent);
      for (var i = 0; i < 40 && !parentHandle.state.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final pstate = parentHandle.state;
      // ignore: avoid_print
      print('PROBE parent.ready=${pstate.ready} rows=${pstate.rows.length} '
          'firstRowId=${pstate.firstRowId}');

      // ---- A. dump agent-ish toolCall rows (window + history) ------------
      void dumpAgentRow(Map<String, dynamic> r) {
        // ignore: avoid_print
        print('PROBE agentRow rowId=${r['rowId']} status=${r['status']} '
            'toolName=${r['toolName']}\n'
            '  input=${cut(r['inputText'], 500)}\n'
            '  output=${cut(r['outputText'], 500)}\n'
            '  extraKeys=${r.keys.where((k) => !const [
                  'rowId',
                  'status',
                  'toolName',
                  'inputText',
                  'outputText',
                  'kind',
                  'turnId',
                  'entityId',
                  'productTurnId',
                  'visibility',
                  'createdAt',
                  'createdAtSeq',
                ].contains(k)).toList()}');
      }

      var agentRows = pstate.rows.where((r) =>
          r['kind'] == 'toolCall' &&
          RegExp('agent|task', caseSensitive: false)
              .hasMatch('${r['toolName']}'));
      for (final r in agentRows) {
        dumpAgentRow(r);
      }
      if (agentRows.isEmpty) {
        // Page back through history for completed Agent calls.
        var before = pstate.firstRowId;
        for (var page = 0; page < 6 && before != null && before > 0; page++) {
          final res = await session.callChannel('zcode-agent',
              'conversationRowsRangeV4', [
            {...session.offPeakScope, 'sessionId': parent, 'limit': 60, 'beforeRowId': before}
          ]);
          List? rows;
          final ro = res is Map ? res['rows'] : null;
          if (ro is Map) rows = ro['window'] as List? ?? ro['rows'] as List?;
          if (ro is List) rows = ro;
          rows ??= res is List ? res : null;
          if (rows == null || rows.isEmpty) break;
          for (final r in rows.whereType<Map>()) {
            final m = r.cast<String, dynamic>();
            if (m['kind'] == 'toolCall' &&
                RegExp('agent|task', caseSensitive: false)
                    .hasMatch('${m['toolName']}')) {
              dumpAgentRow(m);
            }
          }
          final first = rows
              .whereType<Map>()
              .map((e) => (e['rowId'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          if (first.isEmpty) break;
          final newBefore = first.reduce((a, b) => a < b ? a : b);
          if (newBefore <= 1 || newBefore == before) break;
          before = newBefore;
        }
      }

      // ---- B. subagent live state ----------------------------------------
      final subRows = pstate.rows.where((r) => r['kind'] == 'subagent');
      for (final r in subRows) {
        // ignore: avoid_print
        print('PROBE subagentRow rowId=${r['rowId']} '
            'child=${cut(r['childSessionId'], 50)} type=${r['subagentType']} '
            'status=${r['status']} workId=${cut(r['workId'], 46)} '
            'summary=${cut(r['summaryText'], 200)}');
      }
      final subs = pstate.snapshot?['subagents'];
      // ignore: avoid_print
      print('PROBE subagents=${cut(subs, 600)}');
      final works = pstate.snapshot?['backgroundWorks'];
      if (works is List) {
        // ignore: avoid_print
        print('PROBE works=${works.whereType<Map>().map((w) => '${w['kind']}:${w['status']}:${cut(w['childSessionId'], 46)}:${cut(w['title'], 60)}').toList()}');
      }

      // Watch summaryText streaming for 30s.
      final t0 = DateTime.now();
      final base = {
        for (final r in subRows) '${r['childSessionId']}': '${r['summaryText']}'
      };
      while (DateTime.now().difference(t0) < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(seconds: 5));
        for (final r in pstate.rows.where((r) => r['kind'] == 'subagent')) {
          final k = '${r['childSessionId']}';
          final now = '${r['summaryText']}';
          if (base[k] != now) {
            base[k] = now;
            // ignore: avoid_print
            print('PROBE stream[${r['status']}] +${DateTime.now().difference(t0).inSeconds}s '
                'len=${now.length} tail=${cut(now.substring(now.length > 120 ? now.length - 120 : 0), 130)}');
          }
        }
      }

      // ---- C. child subscribes -------------------------------------------
      Future<void> probeChild(String child, String tag, {int capSeconds = 25}) async {
        final sw = Stopwatch()..start();
        try {
          final h = await session.subscribe(child);
          for (var i = 0;
              i < capSeconds * 2 && !h.state.ready && sw.elapsed < Duration(seconds: capSeconds);
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          // ignore: avoid_print
          print('PROBE child[$tag] ${cut(child, 50)} ready=${h.state.ready} '
              'rows=${h.state.rows.length} in=${sw.elapsed.inSeconds}s');
          // rowsRange cross-check regardless of subscribe outcome.
          try {
            final res = await session.callChannel('zcode-agent',
                'conversationRowsRangeV4', [
                  {...session.offPeakScope, 'sessionId': child, 'limit': 5}
                ]);
            final n = res is Map
                ? ((res['rows'] as List?) ?? ((res['rows'] as Map?)?['window'] as List?) ?? ((res['rows'] as Map?)?['rows'] as List?))?.length
                : (res as List?)?.length;
            // ignore: avoid_print
            print('PROBE child[$tag].rowsRange rows=$n '
                'hasMore=${res is Map ? res['hasMore'] : '-'}');
          } catch (e) {
            // ignore: avoid_print
            print('PROBE child[$tag].rowsRange FAILED: ${cut(e, 200)}');
          }
          await h.close();
        } catch (e) {
          // ignore: avoid_print
          print('PROBE child[$tag] subscribe FAILED after '
              '${sw.elapsed.inSeconds}s: ${cut(e, 200)}');
        }
      }

      // Fresh running child first (small snapshot), then a big ended one.
      final worksList = works is List ? works.whereType<Map>().toList() : const <Map>[];
      String? fresh;
      for (final w in worksList) {
        if (w['kind'] == 'subagent' &&
            '${w['status'] ?? ''}'.contains('run') &&
            '${w['childSessionId'] ?? ''}'.isNotEmpty) {
          fresh = '${w['childSessionId']}';
          break;
        }
      }
      final endedKids = worksList
          .where((w) =>
              w['kind'] == 'subagent' && '${w['childSessionId'] ?? ''}'.isNotEmpty)
          .map((w) => '${w['childSessionId']}')
          .toSet();
      final subInfo = subs is Map ? subs['childSessionIds'] : null;
      if (subInfo is List) {
        endedKids.addAll(subInfo.whereType<String>());
      }

      // rowsRange on the parent doubles as the bridge-alive canary.
      Future<void> canary(String tag) async {
        try {
          await session.callChannel('zcode-agent',
              'conversationRowsRangeV4', [
                {...session.offPeakScope, 'sessionId': parent, 'limit': 1}
              ]);
          // ignore: avoid_print
          print('PROBE bridge alive after $tag');
        } catch (e) {
          // ignore: avoid_print
          print('PROBE bridge rpc after $tag FAILED: ${cut(e, 150)}');
        }
      }

      if (fresh != null) {
        await probeChild(fresh, 'fresh');
        await canary('fresh');
      }

      // Probe the last few ended children (the detail-page large-snapshot
      // repro); each prints ready/rows/latency plus a rowsRange cross-check.
      final endedList = endedKids.toList();
      final tailKids = endedList
          .skip(endedList.length > 3 ? endedList.length - 3 : 0)
          .toList();
      for (var i = 0; i < tailKids.length; i++) {
        await probeChild(tailKids[i], 'ended$i');
        await canary('ended$i');
      }

      await parentHandle.close();
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
