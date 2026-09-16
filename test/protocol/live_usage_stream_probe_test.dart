import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/channel_client.dart';
import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): passive dump of `bots:task-stream`
/// broadcast messages — `usage_update` field shapes above all — plus a
/// cross-check of the app pipeline (`DeviceSession.subscribe` →
/// `ConversationState.contextUsage`) against the raw events. Purely
/// read-only: nothing is called except a conversation subscription.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live usage_update stream probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');

    final session = DeviceSession(deviceId: 'probe-usage', params: params);

    var usageUpdates = 0;
    final otherTypes = <String, int>{};
    void onBroadcast(dynamic data) {
      if (data is! Map) return;
      if (data['channel'] != 'bots:task-stream') {
        // ignore: avoid_print
        print('BROADCAST other channel: ${data['channel']}');
        return;
      }
      final payload = data['payload'];
      if (payload is! Map) return;
      final event = payload['event'];
      final type = event is Map ? '${event['type']}' : '?';
      if (type == 'usage_update') {
        usageUpdates++;
        // ignore: avoid_print
        print('USAGE_UPDATE task=${payload['taskId']} '
            'event=${jsonEncode(event)}');
      } else {
        otherTypes[type] = (otherTypes[type] ?? 0) + 1;
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      for (var i = 0; i < 30 && session.conversation == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(session.conversation, isNotNull,
          reason: 'conversation transport never came up');
      final channels = session.conversation!.session.channels;
      channels.addEventListener(Channels.broadcast, 'onMessage', onBroadcast);

      final tasks = session.relayTasks;
      // ignore: avoid_print
      print('PROBE relayTasks=${tasks.length}');
      String? target;
      for (final t in tasks.take(6)) {
        // ignore: avoid_print
        print('PROBE task keys=${t.keys.toList()} '
            'taskId=${t['taskId']} state=${t['state'] ?? t['status']} '
            'title=${t['title'] ?? t['name']}');
        final st = '${t['state'] ?? t['status'] ?? ''}';
        if (target == null &&
            (st.contains('running') || st.contains('streaming'))) {
          target = '${t['taskId']}';
        }
      }
      target ??= tasks.isNotEmpty ? '${tasks.first['taskId']}' : null;
      // ignore: avoid_print
      print('PROBE subscribing task=$target');
      if (target == null) return;

      final handle = await session.subscribe(target);
      for (var i = 0; i < 20 && handle.state.snapshot == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final snap = handle.state.snapshot ?? const {};
      final snapUsage = snap['usage'];
      // ignore: avoid_print
      print('PROBE snapshotKeys=${snap.keys.toList()}');
      // ignore: avoid_print
      print('PROBE snapshot.usage=${jsonEncode(snapUsage)}');
      final before = handle.state.contextUsage;
      // ignore: avoid_print
      print('PROBE contextUsage.before '
          'used=${before.used} max=${before.max} hitRate=${before.hitRate} '
          'hasData=${before.hasData}');

      // Passive window: the desktop broadcasts usage_update while its own
      // sessions burn tokens. 90s is enough for a few rounds.
      await Future<void>.delayed(const Duration(seconds: 90));
      // ignore: avoid_print
      print('PROBE window done: usageUpdates=$usageUpdates '
          'otherTaskStreamTypes=$otherTypes');
      final after = handle.state.contextUsage;
      // ignore: avoid_print
      print('PROBE contextUsage.after '
          'used=${after.used}/${after.max} hitRate=${after.hitRate} '
          'breakdown=${after.breakdown.map((b) => '${b.source}:${b.chars}').toList()}');
      await handle.close();
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
