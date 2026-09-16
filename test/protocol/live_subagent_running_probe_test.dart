import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): diagnose the subagent-detail spinner —
/// subscribe the RUNNING parent session, find its live subagent rows, then
/// subscribe a running child session and watch ConversationState for frames.
/// Cross-checks the server-side row store via conversationRowsRangeV4 so we
/// can tell "no snapshot pushed" apart from "session actually empty".
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live running-subagent subscribe probe', () async {
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

      // 1) Find the running session via the relay task overview.
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

      // 2) Subscribe the parent; collect subagent-ish rows.
      final parentHandle = await session.subscribe(parent);
      for (var i = 0; i < 40 && !parentHandle.state.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final prows = parentHandle.state.rows;
      // ignore: avoid_print
      print('PROBE parent.ready=${parentHandle.state.ready} '
          'rows=${prows.length}');
      final kids = <String>[];
      for (final r in prows) {
        if (r['kind'] == 'subagent') {
          kids.add('${r['childSessionId']}');
          // ignore: avoid_print
          print('PROBE subagentRow sid=${r['childSessionId']} '
              'status=${r['status']} type=${r['subagentType']}');
        }
      }
      final works = parentHandle.state.snapshot?['backgroundWorks'];
      if (works is List) {
        for (final w in works.whereType<Map>()) {
          // ignore: avoid_print
          print('PROBE work kind=${w['kind']} status=${w['status']} '
              'endedAt=${w['endedAt'] ?? w['completedAt'] ?? '-'} '
              'child=${w['childSessionId']} title=${w['title']}');
        }
      }
      // Prefer a RUNNING subagent child (the spinner case); fall back to
      // the newest child overall.
      final subWorks = works is List
          ? works.whereType<Map>().where((w) => w['kind'] == 'subagent')
          : const <Map>[];
      final runningKid = subWorks
          .where((w) => '${w['status'] ?? ''}'.contains('run') ||
              (w['endedAt'] == null && w['completedAt'] == null))
          .map((w) => '${w['childSessionId'] ?? ''}')
          .where((c) => c.isNotEmpty)
          .firstOrNull;
      if (runningKid != null) kids.insert(0, runningKid);
      for (final w in subWorks) {
        final c = '${w['childSessionId'] ?? ''}';
        if (c.isNotEmpty && !kids.contains(c)) kids.add(c);
      }
      // ignore: avoid_print
      print('PROBE kids order: ${kids.take(3).join(' , ')}');
      if (kids.isEmpty) {
        // ignore: avoid_print
        print('PROBE no subagent rows found on parent — nothing to test');
        return;
      }

      // 3) Subscribe the first child; watch state for 15s.
      final child = kids.first;
      final childHandle = await session.subscribe(child);
      // ignore: avoid_print
      print('PROBE child subscribed $child');
      final changes = <String>[];
      void listener() => changes.add(
          'ready=${childHandle.state.ready} rows=${childHandle.state.rows.length} '
          'seq=${childHandle.state.seq}');
      childHandle.state.addListener(listener);
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (childHandle.state.ready) break;
      }
      childHandle.state.removeListener(listener);
      // ignore: avoid_print
      print('PROBE child.after15s ready=${childHandle.state.ready} '
          'rows=${childHandle.state.rows.length} '
          'changes=${changes.length} ${changes.take(3).join(" | ")}');

      // 4) Cross-check: does the server have rows for this child at all?
      try {
        final res = await session.callChannel('zcode-agent',
            'conversationRowsRangeV4', [
          {
            ...session.offPeakScope,
            'sessionId': child,
            'limit': 5,
          }
        ]);
        final n = res is Map ? (res['rows'] as List?)?.length : null;
        // ignore: avoid_print
        print('PROBE child.rowsRange rows=$n '
            'hasMore=${res is Map ? res['hasMore'] : '-'} '
            'epoch=${res is Map ? res['atLogEpoch'] : '-'}');
      } catch (e) {
        // ignore: avoid_print
        print('PROBE child.rowsRange FAILED: $e');
      }

      await childHandle.close();
      await parentHandle.close();
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
