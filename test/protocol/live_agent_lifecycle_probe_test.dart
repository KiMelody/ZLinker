import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): full subagent lifecycle capture.
/// A background Explore target is dispatched by the main agent right before
/// this test starts. We subscribe BOTH the parent and the (fresh) child
/// session and poll-diff for up to 3 minutes:
///  - Agent toolCall row: full JSON at every change (does `output` gain the
///    result? does `_meta.zcode.taskNotification` / `thought` ever appear?)
///  - `subagent` row: status + summaryText changes (streaming cadence)
///  - snapshot.subagents / backgroundWorks transitions
///  - child rows: which (kind, toolName, status) shapes stream live — the
///    design basis for a "current action" label.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live agent lifecycle capture', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('PROBE ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe9', params: params);

    String cut(Object? v, [int n = 300]) {
      var s = '$v';
      if (s.length > n) s = '${s.substring(0, n)}…(${s.length})';
      return s;
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      final parent = '${session.relayTasks.firstOrNull?['taskId'] ?? ''}';
      // ignore: avoid_print
      print('PROBE parent=$parent');

      final parentHandle = await session.subscribe(parent);
      for (var i = 0; i < 40 && !parentHandle.state.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final pstate = parentHandle.state;

      // Locate the freshest Agent row + its subagent row.
      Map<String, dynamic>? agentRow;
      Map<String, dynamic>? subRow;
      String? childSessionId;
      final t0 = DateTime.now();
      while (DateTime.now().difference(t0) < const Duration(seconds: 20)) {
        for (final r in pstate.rows) {
          if (r['kind'] == 'toolCall' &&
              '${r['toolName'] ?? ''}'.toLowerCase() == 'agent' &&
              (agentRow == null ||
                  (r['rowId'] as num?)! > (agentRow['rowId'] as num?)!)) {
            agentRow = r;
          }
          if (r['kind'] == 'subagent' &&
              (subRow == null ||
                  (r['rowId'] as num?)! > (subRow['rowId'] as num?)!)) {
            subRow = r;
          }
        }
        childSessionId = subRow == null
            ? null
            : '${subRow['childSessionId'] ?? ''}';
        if (agentRow != null && childSessionId != null && childSessionId.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // ignore: avoid_print
      print('PROBE agentRow=${agentRow == null ? '-' : cut(agentRow['rowId'])} '
          'child=$childSessionId');

      // Subscribe the child (live action shapes).
      ChatHandle? childHandle;
      if (childSessionId != null && childSessionId.isNotEmpty) {
        childHandle = await session.subscribe(childSessionId);
      }

      // Poll-diff loop.
      var lastAgentJson = '';
      var lastSubJson = '';
      var lastSubsSnap = '';
      var lastWorksSnap = '';
      final childShapes = <String>{};
      String? lastChildAction;
      for (var i = 0; i < 180; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));

        for (final r in pstate.rows) {
          if (r['kind'] == 'toolCall' &&
              '${r['toolName'] ?? ''}'.toLowerCase() == 'agent' &&
              agentRow != null &&
              r['rowId'] == agentRow['rowId']) {
            final j = r.toString();
            if (j != lastAgentJson) {
              lastAgentJson = j;
              // ignore: avoid_print
              print('PROBE AGENT[${r['status']}] keys=${r.keys.toList()} '
                  'output=${cut(r['output'], 200)} '
                  'raw=${cut(r['raw'], 260)}');
              final raw = r['raw'];
              if (raw is Map) {
                final meta = raw['_meta'];
                // ignore: avoid_print
                print('PROBE AGENT._meta=${cut(meta, 400)}');
              }
            }
          }
          if (r['kind'] == 'subagent' && subRow != null && r['rowId'] == subRow['rowId']) {
            final j = '${r['status']}|${r['summaryText']}';
            if (j != lastSubJson) {
              lastSubJson = j;
              // ignore: avoid_print
              print('PROBE SUB[+${DateTime.now().difference(t0).inSeconds}s] '
                  'status=${r['status']} len=${'${r['summaryText'] ?? ''}'.length} '
                  'tail=${cut('${r['summaryText'] ?? ''}'.substring('${r['summaryText'] ?? ''}'.length > 100 ? '${r['summaryText'] ?? ''}'.length - 100 : 0), 110)}');
            }
          }
        }

        final subs = pstate.snapshot?['subagents'];
        final subsKey = cut(subs, 500);
        if (subsKey != lastSubsSnap) {
          lastSubsSnap = subsKey;
          final running = subs is Map ? subs['running'] : null;
          // ignore: avoid_print
          print('PROBE SUBSNAP[+${DateTime.now().difference(t0).inSeconds}s] '
              'running=${cut(running, 260)}');
        }
        final works = pstate.snapshot?['backgroundWorks'];
        final subWorks = works is List
            ? works.whereType<Map>().where((w) => w['kind'] == 'subagent').toList()
            : const <Map>[];
        final worksKey = subWorks
            .map((w) => '${cut(w['childSessionId'], 20)}:${w['status']}:${w['endedAt']}')
            .join(';');
        if (worksKey != lastWorksSnap) {
          lastWorksSnap = worksKey;
          // ignore: avoid_print
          print('PROBE WORKS[+${DateTime.now().difference(t0).inSeconds}s] '
              '${subWorks.length} entries; newest=${subWorks.isEmpty ? '-' : cut(subWorks.last, 220)}');
        }

        final ch = childHandle;
        if (ch != null && ch.state.ready) {
          final rows = ch.state.rows;
          String? action;
          for (final r in rows.reversed) {
            if (r['kind'] == 'toolCall') {
              action = '${r['toolName']}:${r['status']}:'
                  '${cut(r['inputText'], 60)}';
              break;
            }
          }
          if (action != null && !childShapes.contains(action)) {
            childShapes.add(action);
            // ignore: avoid_print
            print('PROBE CHILD[+${DateTime.now().difference(t0).inSeconds}s] '
                'lastTool=$action rows=${rows.length}');
          }
          lastChildAction = action;
        }
      }
      // ignore: avoid_print
      print('PROBE DONE lastChildAction=$lastChildAction '
          'childShapes=${childShapes.length}');
      await childHandle?.close();
      await parentHandle.close();
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
