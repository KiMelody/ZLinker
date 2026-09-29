import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live probe (ZLINKER_PROBE_URL): certifies the desktop `file` channel's
/// fileService surface for the file-preview task (research
/// official-file-preview-bundle-analysis.md §1.1) — ① which candidate method
/// names answer, ② the args scope shape (`{path}` direct vs
/// `{workspacePath, path}`), ③ the answer field names
/// (dataBase64/mediaType/size · text/hasMore · type/size). Evidence lands in
/// the task's research doc; the port's scope shape is fixed from it.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live file-service probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe-file', params: params);

    Future<void> tryCall(String method, Map<String, dynamic> args) async {
      try {
        final res =
            await session.callChannel('file', method, <Object?>[args]);
        // ignore: avoid_print
        print('PROBE file.$method args=$args OK '
            '${res is Map ? 'keys=${res.keys.take(10).toList()} '
                'types=${res.values.take(10).map((v) => v.runtimeType).toList()}'
            : res.runtimeType}');
        if (res is Map) {
          for (final e in res.entries.take(10)) {
            final v = e.value;
            final shown = v is String && v.length > 60
                ? '<${v.length} chars> ${v.substring(0, 40)}…'
                : v;
            // ignore: avoid_print
            print('PROBE   ${e.key} = $shown');
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('PROBE file.$method args=$args ERR $e');
      }
    }

    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);

      // Wait briefly for the relay workspace list so the scope shape can be
      // tried with a real workspacePath (connect auto-opens the first one).
      String? wsPath = session.workspacePath;
      for (var i = 0; i < 10 && wsPath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        wsPath = session.workspacePath ??
            session.workspaces.firstOrNull?['workspacePath'] as String?;
      }
      // ignore: avoid_print
      print('PROBE workspacePath=$wsPath');

      const methods = ['stat', 'readMediaPreview', 'readTextFile'];
      // Round 1 (certified 2026-09-29): relative paths resolve against the
      // desktop process CWD and args.workspacePath is IGNORED — both shapes
      // ENOENT'd identically. Round 2: absolute paths only.
      final shapes = <Map<String, dynamic>>[
        if (wsPath != null) {'path': '$wsPath\\package.json'},
        if (wsPath != null)
          {'workspacePath': wsPath, 'path': '$wsPath\\package.json'},
      ];
      for (final method in methods) {
        for (final shape in shapes) {
          await tryCall(method, shape);
        }
      }
      // Text pagination params ride the same scope shapes.
      for (final shape in shapes) {
        await tryCall('readTextFile', {...shape, 'offset': 0, 'length': 1024});
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
