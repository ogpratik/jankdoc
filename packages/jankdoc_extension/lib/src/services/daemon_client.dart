import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jankdoc_core/jankdoc_core.dart';

/// HTTP client for the JankDoc Analysis Daemon (port 9101 by default).
///
/// Responsibilities:
///   - REST: /health, /info, /sessions
///   - SSE: GET /diagnoses/stream — reconnects with exponential back-off
///
/// Create one instance per discovered daemon URL and [dispose] when done.
final class DaemonClient {
  DaemonClient(this.baseUrl) : _client = http.Client();

  final String baseUrl;
  final http.Client _client;

  // ── Health ────────────────────────────────────────────────────────────────

  Future<bool> isAlive() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Info ──────────────────────────────────────────────────────────────────

  Future<DaemonInfo> fetchInfo() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/info'))
        .timeout(const Duration(seconds: 5));
    _checkStatus(response);
    return DaemonInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<List<Session>> fetchSessions({int limit = 20}) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/sessions?limit=$limit'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final list = json['sessions'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(Session.fromJson)
        .toList();
  }

  Future<Session?> fetchSession(String id) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/sessions/$id'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 404) return null;
    _checkStatus(response);
    return Session.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ── Diagnosis SSE stream ──────────────────────────────────────────────────

  /// Broadcast stream of [Diagnosis] objects from the daemon SSE endpoint.
  ///
  /// Reconnects automatically with capped exponential back-off (1s → 30s).
  /// Callers can cancel the subscription to stop listening; the generator
  /// exits cleanly on the next reconnect attempt.
  Stream<Diagnosis> diagnosisStream() => _sseStream().asBroadcastStream();

  Stream<Diagnosis> _sseStream() async* {
    var backoff = const Duration(seconds: 1);
    const maxBackoff = Duration(seconds: 30);

    while (true) {
      try {
        final request = http.Request(
          'GET',
          Uri.parse('$baseUrl/diagnoses/stream'),
        );
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw StateError('SSE endpoint returned ${response.statusCode}');
        }

        backoff = const Duration(seconds: 1); // reset on successful connect

        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!line.startsWith('data: ')) continue;
          final payload = line.substring(6).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            yield Diagnosis.fromJson(json);
          } catch (_) {
            // Malformed SSE frame — skip gracefully
          }
        }
      } catch (_) {
        await Future<void>.delayed(backoff);
        backoff = backoff * 2;
        if (backoff > maxBackoff) backoff = maxBackoff;
      }
    }
  }

  void dispose() => _client.close();

  static void _checkStatus(http.Response response) {
    if (response.statusCode >= 400) {
      throw StateError(
        'Daemon HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}

// ── Value objects ─────────────────────────────────────────────────────────────

final class DaemonInfo {
  const DaemonInfo({
    required this.version,
    required this.modelId,
    required this.ollamaUrl,
  });

  final String version;
  final String modelId;
  final String ollamaUrl;

  factory DaemonInfo.fromJson(Map<String, dynamic> json) => DaemonInfo(
        version: json['version'] as String? ?? '?',
        modelId: json['model'] as String? ?? '?',
        ollamaUrl: json['ollama_url'] as String? ?? '?',
      );
}

/// The three states the extension can be in relative to the daemon.
enum DaemonConnectionState {
  /// VM Service extension not yet registered — daemon not started.
  disconnected,

  /// VM Service extension found; establishing first HTTP contact.
  connecting,

  /// /health returned 200.
  connected,
}
