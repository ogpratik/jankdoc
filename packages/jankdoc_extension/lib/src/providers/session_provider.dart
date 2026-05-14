import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import 'daemon_provider.dart';

/// Recent sessions from the daemon's SQLite history.
final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  final client = ref.watch(daemonClientProvider);
  if (client == null) return const [];
  return client.fetchSessions(limit: 20);
});

/// The session ID currently selected in the session history panel.
final selectedSessionIdProvider = StateProvider<String?>((_) => null);

/// The full [Session] object for the selected ID.
final selectedSessionProvider = FutureProvider<Session?>((ref) async {
  final id = ref.watch(selectedSessionIdProvider);
  if (id == null) return null;
  final client = ref.watch(daemonClientProvider);
  if (client == null) return null;
  return client.fetchSession(id);
});

/// Whether the session history sidebar is expanded.
final sessionPanelExpandedProvider = StateProvider<bool>((_) => false);
