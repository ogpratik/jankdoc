import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/daemon_client.dart';

// ── URL discovery via VM Service ──────────────────────────────────────────────

/// Reads `ext.jankdoc.daemonUrl` from the connected app's VM Service.
///
/// Returns null when:
///   - No app is connected in DevTools
///   - JankDoc.attach() hasn't been called (extension not registered)
///   - The daemon hasn't started yet
///
/// Retries every 3 seconds until a URL is found.
final daemonUrlProvider = StreamProvider<String?>((ref) async* {
  yield null; // initial state while probing

  while (true) {
    try {
      final service = serviceManager.service;
      if (service != null) {
        final isolateId =
            serviceManager.isolateManager.mainIsolate.value?.id;
        if (isolateId != null) {
          final result = await service.callServiceExtension(
            'ext.jankdoc.daemonUrl',
            isolateId: isolateId,
          );
          final url = result.json?['url'] as String?;
          if (url != null && url.isNotEmpty) {
            yield url;
            return; // URL found — stop polling
          }
        }
      }
    } catch (_) {
      // Extension not yet registered — keep polling
    }

    yield null;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});

// ── Daemon client singleton ───────────────────────────────────────────────────

/// The active [DaemonClient] derived from the discovered URL.
/// Automatically recreated when the URL changes.
final daemonClientProvider = Provider<DaemonClient?>((ref) {
  final urlAsync = ref.watch(daemonUrlProvider);
  final url = urlAsync.valueOrNull;
  if (url == null) return null;

  final client = DaemonClient(url);
  ref.onDispose(client.dispose);
  return client;
});

// ── Daemon info ───────────────────────────────────────────────────────────────

final daemonInfoProvider = FutureProvider<DaemonInfo?>((ref) async {
  final client = ref.watch(daemonClientProvider);
  if (client == null) return null;
  try {
    return await client.fetchInfo();
  } catch (_) {
    return null;
  }
});

// ── Connection health polling ─────────────────────────────────────────────────

/// Emits [DaemonConnectionState] by polling /health every 5 seconds.
final connectionStateProvider =
    StreamProvider<DaemonConnectionState>((ref) async* {
  final urlAsync = ref.watch(daemonUrlProvider);

  if (urlAsync.isLoading) {
    yield DaemonConnectionState.disconnected;
    return;
  }

  final url = urlAsync.valueOrNull;
  if (url == null) {
    yield DaemonConnectionState.disconnected;
    return;
  }

  yield DaemonConnectionState.connecting;

  final client = ref.watch(daemonClientProvider);
  if (client == null) {
    yield DaemonConnectionState.disconnected;
    return;
  }

  while (true) {
    final alive = await client.isAlive();
    yield alive
        ? DaemonConnectionState.connected
        : DaemonConnectionState.connecting;
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});

// ── 30-second reachability timeout ───────────────────────────────────────────

/// Emits `true` when a daemon URL is known but /health hasn't responded
/// within 30 seconds. Resets (rebuilds from false) whenever the URL changes.
///
/// Used to drive the "Daemon not reachable" actionable banner so the user
/// knows to check their `JankDoc.attach()` call, rather than seeing an
/// eternally-spinning yellow dot with no explanation.
final daemonTimedOutProvider = StreamProvider<bool>((ref) async* {
  yield false;

  final urlAsync = ref.watch(daemonUrlProvider);
  if (urlAsync.valueOrNull == null) return;

  // URL found — count down 30 seconds in 3-second increments.
  const timeout = Duration(seconds: 30);
  const pollInterval = Duration(seconds: 3);
  var elapsed = Duration.zero;

  while (elapsed < timeout) {
    await Future<void>.delayed(pollInterval);
    elapsed += pollInterval;

    final state = ref.read(connectionStateProvider).valueOrNull;
    if (state == DaemonConnectionState.connected) {
      yield false;
      return; // Daemon came up within the window — no banner.
    }
  }

  // Still unreachable after 30 seconds.
  yield true;
});
