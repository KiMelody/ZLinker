import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): dumps what the phone's model-config UI
/// reads — model-provider.getAll (providers page) and the conversation
/// snapshot's availability payload (chat model picker) — to reproduce
/// "all model configs disappeared" reports.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live model-provider availability probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe6', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      for (final method in ['getAll', 'getAllCached']) {
        try {
          final res =
              await session.callChannel('model-provider', method, const []);
          if (res is Map) {
            // ignore: avoid_print
            print('PROBE $method keys=${res.keys.toList()}');
            final providers = res['providers'];
            if (providers is List) {
              // ignore: avoid_print
              print('PROBE $method providers=${providers.length} '
                  'ids=${providers.take(10).map((p) => p is Map ? '${p['id']}' : '$p').toList()}');
            }
          } else if (res is List) {
            // ignore: avoid_print
            print('PROBE $method listLen=${res.length} '
                'ids=${res.take(10).map((p) => p is Map ? '${p['id']}' : '$p').toList()}');
          } else {
            // ignore: avoid_print
            print('PROBE $method type=${res.runtimeType} value=$res');
          }
        } catch (e) {
          // ignore: avoid_print
          print('PROBE $method failed: $e');
        }
      }

      final tasks = [
        for (final t in session.relayTasks)
          if ('${t['taskId']}'.isNotEmpty) '${t['taskId']}',
      ];
      for (final taskId in tasks.take(2)) {
        final handle = await session.subscribe(taskId);
        for (var i = 0; i < 10 && handle.state.snapshot == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final snap = handle.state.snapshot;
        // ignore: avoid_print
        print('PROBE task=$taskId availability=${snap?['availability']} '
            'config=${snap?['config']}');
        await handle.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
