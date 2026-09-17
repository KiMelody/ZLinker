import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): how the official web remote's fixed
/// model fetch (readWorkspacePresentation → workspace/readPresentation)
/// is (or is not) exposed to the phone terminal bridge. Tries the service
/// name and the protocol path across the reachable channels.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live workspace presentation probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe12123g', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      final ws = session.activeWorkspace;
      final scope = {
        'workspacePath': ws?['workspacePath'],
        if (ws?['workspaceIdentity'] != null)
          'workspaceIdentity': ws?['workspaceIdentity'],
      };
      // ignore: avoid_print
      print('PROBE scope=$scope');

      Future<void> tryCall(String channel, String method,
          [List<Object?> args = const []]) async {
        try {
          final res = await session.callChannel(channel, method, args);
          // ignore: avoid_print
          print('PROBE HIT  $channel.$method -> '
              '${res is Map ? 'keys=${res.keys.toList()}' : res}');
        } catch (e) {
          // ignore: avoid_print
          print('PROBE miss $channel.$method: $e');
        }
      }

      for (final channel in ['zcode-agent', 'zcode-task']) {
        await tryCall(channel, 'readWorkspacePresentation', [scope]);
        await tryCall(channel, 'readPresentation', [scope]);
        await tryCall(channel, 'workspace/readPresentation', [scope]);
      }

      // Full dump of the hit: slashCommands content + mode structure (the
      // official web derives configOptions from mode via rhe()).
      try {
        final res = await session.callChannel(
            'zcode-agent', 'readWorkspacePresentation', [scope]);
        if (res is Map) {
          final cmds = res['slashCommands'];
          final cmdCount = cmds is List ? '${cmds.length}' : '?';
          // ignore: avoid_print
          print('PROBE slashCommands($cmdCount): ${cmds is List ? cmds.take(8) : cmds}');
          final mode = res['mode'];
          // ignore: avoid_print
          print('PROBE mode type=${mode.runtimeType} '
              'keys=${mode is Map ? mode.keys.toList() : mode}');
          if (mode is Map) {
            for (final e in mode.entries.take(10)) {
              var line = 'PROBE mode[${e.key}]=${e.value}';
              if (line.length > 220) line = line.substring(0, 220);
              // ignore: avoid_print
              print(line);
            }
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('PROBE dump err: $e');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
