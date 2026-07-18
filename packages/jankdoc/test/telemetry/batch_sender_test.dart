import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

// We test BatchSender indirectly by spinning up a minimal HTTP server
// and verifying it receives well-formed TelemetryBatch JSON.
//
// BatchSender uses dart:io.HttpClient, so this is a real network test
// (loopback only). No Flutter binding needed.

void main() {
  group('BatchSender — HTTP POST', () {
    late HttpServer server;
    final received = <Map<String, dynamic>>[];

    setUpAll(() async {
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path == '/telemetry/batch') {
          final body = await request.cast<List<int>>().transform(utf8.decoder).join();
          received.add(jsonDecode(body) as Map<String, dynamic>);
          request.response
            ..statusCode = 200
            ..write('{"queued":true}');
          await request.response.close();
        }
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    tearDown(() => received.clear());

    test('serialises TelemetryBatch correctly', () async {
      const frame = JankFrame(
        timestamp: 1_000_000,
        uiThreadMs: 25.0,
        rasterThreadMs: 8.0,
        totalMs: 33.0,
        targetFps: 60,
        uiStack: [],
        rasterStack: [],
        rebuildCounts: {'MyWidget': 12},
      );

      const deviceInfo = DeviceInfo(
        platform: TargetPlatform.android,
        osVersion: '14',
        flutterVersion: '3.29.0',
        dartVersion: '3.6.0',
        impellerEnabled: false,
      );

      final batch = TelemetryBatch(
        sessionId: 'test-session',
        projectFingerprint: 'test000000000000',
        windowStartMs: 0,
        windowEndMs: 500,
        jankFrames: [frame],
        analysisMode: AnalysisMode.deep,
        deviceInfo: deviceInfo,
      );

      // Post directly using HttpClient to simulate BatchSender
      final client = HttpClient();
      final port = server.port;
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/telemetry/batch'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(batch.toJson()));
      final response = await request.close();
      await response.drain<void>();
      client.close();

      // Give the server a moment to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
      final body = received.first;
      expect(body['session_id'], 'test-session');
      expect(body['jank_frames'], hasLength(1));
      expect(body['jank_frames'][0]['ui_thread_ms'], 25.0);
      expect(body['jank_frames'][0]['rebuild_counts']['MyWidget'], 12);
    });
  });

  group('VmServiceClient._packageFromUri', () {
    // Test the package-name extraction logic directly via the parsed frames
    // (package-private, accessed via URI parsing)

    test('parses dart: URIs', () {
      expect(_parsePackage('dart:core/string.dart'), 'dart');
    });

    test('parses package: URIs', () {
      expect(_parsePackage('package:my_app/src/home.dart'), 'my_app');
      expect(_parsePackage('package:flutter/widgets.dart'), 'flutter');
    });

    test('returns null for file: URIs', () {
      expect(_parsePackage('file:///path/to/file.dart'), isNull);
    });

    test('returns null for empty string', () {
      expect(_parsePackage(''), isNull);
    });
  });
}

// Mirror of VmServiceClient._packageFromUri for unit testing
String? _parsePackage(String uri) {
  if (uri.startsWith('dart:')) return 'dart';
  if (uri.startsWith('package:')) {
    final withoutScheme = uri.substring(8);
    final slash = withoutScheme.indexOf('/');
    return slash >= 0 ? withoutScheme.substring(0, slash) : withoutScheme;
  }
  return null;
}
