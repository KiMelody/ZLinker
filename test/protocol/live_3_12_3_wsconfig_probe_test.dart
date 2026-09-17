import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/channel_client.dart';
import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): 3.12.3 workspace-config subscription
/// verification — the C3 (prepareWorkspace replacement) primary data source.
///
/// Subscribes `workspace-config/<key>` via subscribeWorkspaceConfigV4 +
/// onDynamicWorkspaceConfigFrame and dumps configOptions (model/mode/thought
/// candidates, with origin) and slashCommands — specifically checking whether
/// desktop-configured custom models (injected providers) appear.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live workspace-config probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123c', params: params);
    final frames = <String>[];
    void Function()? cancelFrameListener;
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      final transport = session.conversation!;
      await transport.handshake();
      final channels = transport.session.channels;
      final scope = transport.scope;
      // ignore: avoid_print
      print('PROBE scope=$scope connectionId=${transport.connectionId}');

      cancelFrameListener = channels.addEventListener(
        Channels.zcodeAgent,
        'onDynamicWorkspaceConfigFrame',
        (dynamic wire) {
          if (wire is! Map) return;
          if (wire['kind'] != 'complete') return; // fragments: skip in probe
          final inner = wire['frame'];
          if (inner is! Map) return;
          final payload = inner['payload'];
          if (payload is! Map) return;
          if (payload['kind'] == 'snapshot') {
            final snap = payload['snapshot'];
            if (snap is! Map) return;
            final config = snap['config'];
            final opts = config is Map ? config['configOptions'] : null;
            final cmds = config is Map ? config['slashCommands'] : null;
            // ignore: avoid_print
            print('PROBE wsconfig snapshot: logEpoch=${snap['logEpoch']} '
                'configOptions=${opts is List ? opts.length : opts} '
                'slashCommands=${cmds is List ? cmds.length : cmds}');
            if (opts is List) {
              for (final o in opts.whereType<Map>()) {
                // ignore: avoid_print
                print('PROBE option: id=${o['id']} type=${o['type']} '
                    'current=${o['currentValue']} '
                    'values=${(o['options'] as List?)?.map((v) => (v is Map ? '${v['value']}${v['modelProviderName'] != null ? '(${v['modelProviderName']})' : ''}' : '$v')).toList()}');
              }
            }
            frames.add('snapshot');
          } else if (payload['kind'] == 'deltas') {
            frames.add('delta:${(payload['deltas'] as List?)?.length}');
          }
        },
        arg: scope,
      );

      final res = await channels.call(
        Channels.zcodeAgent,
        'subscribeWorkspaceConfigV4',
        [scope],
      );
      // ignore: avoid_print
      print('PROBE subscribeWorkspaceConfigV4 -> $res');

      // Wait for the initial snapshot frame + any later config.updated delta.
      for (var i = 0; i < 18 && frames.isEmpty; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      // ignore: avoid_print
      print('PROBE frames received: ${frames.length} ${frames.take(3)}');
      // Extra settle window to catch a late config.updated delta push.
      await Future<void>.delayed(const Duration(seconds: 8));
      // ignore: avoid_print
      print('PROBE frames after settle: ${frames.length} ${frames.take(5)}');
      expect(frames, isNotEmpty,
          reason: 'workspace-config snapshot should arrive after subscribe');

      // Task-level comparison: getTaskConfigOptions / getTaskModelSelection.
      final relay = session.relayTasks;
      final String? taskId = relay.isNotEmpty
          ? '${relay.first['taskId']}'
          : null;
      if (taskId != null) {
        final taskScope = {
          'workspacePath': '${relay.first['workspacePath']}',
          if (relay.first['workspaceIdentity'] != null)
            'workspaceIdentity': relay.first['workspaceIdentity'],
        };
        try {
          final opts = await session.callChannel('zcode-task',
              'getTaskConfigOptions', [
            {'taskId': taskId, ...taskScope},
          ]);
          if (opts is List) {
            for (final o in opts.whereType<Map>()) {
              // ignore: avoid_print
              print('PROBE taskOption: id=${o['id']} type=${o['type']} '
                  'current=${o['currentValue']} '
                  'values=${(o['options'] as List?)?.map((v) => v is Map ? '${v['value']}' : '$v').toList()}');
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print('PROBE getTaskConfigOptions err: $e');
        }
        try {
          final sel = await session.callChannel('zcode-task',
              'getTaskModelSelection', [
            {'taskId': taskId, ...taskScope},
          ]);
          // ignore: avoid_print
          print('PROBE taskModelSelection: $sel');
        } catch (e) {
          // ignore: avoid_print
          print('PROBE getTaskModelSelection err: $e');
        }
      }
    } finally {
      cancelFrameListener?.call();
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
