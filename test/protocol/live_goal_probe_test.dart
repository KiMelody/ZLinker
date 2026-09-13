import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): dumps the raw goal + backgroundWorks
/// snapshot shapes so the goal panel can be built against real fields.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live goal snapshot probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe4', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      // probe the newest tasks until one carries an active goal
      final tasks = [
        for (final t in session.relayTasks)
          if ('${t['taskId']}'.isNotEmpty) '${t['taskId']}',
      ];
      final childIds = <String>[];
      for (final taskId in tasks.take(6)) {
        final handle = await session.subscribe(taskId);
        for (var i = 0; i < 12 && handle.state.snapshot == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final snap = handle.state.snapshot ?? const {};
        // ignore: avoid_print
        print('PROBE task=$taskId goal=${snap['goal']} '
            'subagents=${snap['subagents']} plan=${snap['plan']} '
            'backgroundWorks=${snap['backgroundWorks']}');
        final rows = handle.state.rows;
        // ignore: avoid_print
        print('PROBE task=$taskId rowCount=${rows.length} rowKinds=${rows
            .map((r) => '${r['kind']}')
            .toSet()
            .toList()}');
        final subs = rows.where((r) => r['kind'] == 'subagent').toList();
        // ignore: avoid_print
        print('PROBE task=$taskId subagentRows=${subs.length}');
        for (final s in subs.take(3)) {
          // ignore: avoid_print
          print('PROBE subagentRow=$s');
        }
        final subagents = snap['subagents'];
        if (subagents is Map && subagents['childSessionIds'] is List) {
          for (final c in subagents['childSessionIds'] as List) {
            if (c is String && c.isNotEmpty) childIds.add(c);
          }
        }
        await handle.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      // Try subscribing to a subagent child session: if accepted, the full
      // child conversation (its rows) is fetchable — the data source for a
      // "subagent detail" view.
      if (childIds.isNotEmpty) {
        final child = childIds.first;
        try {
          final handle = await session.subscribe(child);
          for (var i = 0; i < 12 && handle.state.snapshot == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          final snap = handle.state.snapshot;
          // ignore: avoid_print
          print('PROBE child=$child subscribed=true snapshotKeys='
              '${snap?.keys.toList()}');
          // ignore: avoid_print
          print('PROBE child meta=${snap?['meta']} config=${snap?['config']}');
          // ignore: avoid_print
          print('PROBE child rowCount=${handle.state.rows.length} rowKinds='
              '${handle.state.rows.map((r) => '${r['kind']}').toSet().toList()}');
          await handle.close();
        } catch (e) {
          // ignore: avoid_print
          print('PROBE child=$child subscribed=false error=$e');
        }
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
