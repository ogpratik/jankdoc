/// JankDoc Analysis Daemon entry point.
///
/// Compiled to a native binary: `dart compile exe bin/daemon.dart`
/// Started automatically by JankDoc.attach() or the VS Code companion extension.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/src/analysis/diagnosis_pipeline.dart';
import '../lib/src/analysis/ollama_provider.dart';
import '../lib/src/analysis/output_validator.dart';
import '../lib/src/analysis/vector_store_impl.dart';
import '../lib/src/kb/github_releases_kb_registry.dart';
import '../lib/src/kb/kb_bundle_loader.dart';
import '../lib/src/kb/kb_manager.dart';
import '../lib/src/kb/kb_seeder.dart';
import '../lib/src/session/session_repository.dart';
import '../lib/src/setup_hints.dart';
import '../lib/src/telemetry/telemetry_queue.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port',
        abbr: 'p', defaultsTo: '9101', help: 'Port the daemon listens on.')
    ..addOption('ollama-url',
        defaultsTo: 'http://127.0.0.1:11434',
        help: 'Base URL for the local Ollama instance.')
    ..addOption('model',
        defaultsTo: 'qwen2.5-coder:7b',
        help: 'Ollama model ID used for LLM-tier diagnosis.')
    ..addOption('embed-model',
        defaultsTo: 'nomic-embed-text',
        help: 'Ollama model ID used for KB entry and query embedding.')
    ..addOption('kb-registry',
        defaultsTo: 'https://github.com/ogpratik/jankdoc-kb',
        help: 'GitHub repository URL used as the KB bundle registry. '
            'Format: https://github.com/<owner>/<repo>. '
            'Pass empty string or use --no-kb-registry to disable.')
    ..addFlag('no-kb-registry',
        defaultsTo: false,
        negatable: false,
        help: 'Disable remote KB registry checks. '
            'The daemon will only use locally cached bundles.')
    ..addOption('record',
        valueHelp: 'file',
        help: 'Append every received telemetry batch to <file> as JSON Lines. '
            'Replay it later with `jankdoc:ci --input <file>`.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('JankDoc Analysis Daemon\n\n${parser.usage}');
    exit(0);
  }

  // JANKDOC_PORT env variable overrides --port flag (useful when the default
  // port is taken and the user doesn't want to change their JankDoc.attach() call).
  final portStr =
      io.Platform.environment['JANKDOC_PORT'] ?? results['port'] as String;
  final port = int.tryParse(portStr) ?? 9101;
  final ollamaUrl = results['ollama-url'] as String;
  final modelId = results['model'] as String;
  final embedModelId = results['embed-model'] as String;
  final noRegistry = results['no-kb-registry'] as bool;
  final kbRegistryUrl = noRegistry ? null : (results['kb-registry'] as String?);
  final recordPath = results['record'] as String?;
  final recordSink = recordPath == null
      ? null
      : (File(recordPath)..createSync(recursive: true))
          .openWrite(mode: FileMode.append);

  // ── Already-running guard ──────────────────────────────────────────────────
  // If a healthy daemon is already listening on this port, exit cleanly.
  // This makes the binary safe to call multiple times (e.g. hot-restart).
  try {
    final client = HttpClient();
    final req = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
        .timeout(const Duration(milliseconds: 300));
    final res = await req.close();
    client.close();
    if (res.statusCode == 200) {
      print('[JankDoc] daemon already running on port $port — exiting.');
      exit(0);
    }
  } catch (_) {
    // Port not in use — proceed with normal startup.
  }

  // ── Dependency wiring ──────────────────────────────────────────────────────
  final ruleProvider = BuiltInRuleProvider();
  final ruleEngine = RuleEngine(ruleProvider);
  final vectorStore = InMemoryVectorStore();
  await vectorStore.load(); // loads persisted embeddings from ~/.jankdoc/

  final llmProvider = OllamaProvider(
    baseUrl: ollamaUrl,
    modelId: modelId,
    embedModelId: embedModelId,
  );

  final seeder = KbSeeder(vectorStore: vectorStore, llmProvider: llmProvider);
  final kbLoader = FilesystemKbBundleLoader();

  // Parse owner/repo from the registry URL, e.g.
  //   https://github.com/ogpratik/jankdoc-kb  →  owner=ogpratik, repo=jankdoc-kb
  GithubReleasesKbRegistry? kbRegistry;
  if (kbRegistryUrl != null && kbRegistryUrl.isNotEmpty) {
    final uri = Uri.tryParse(kbRegistryUrl);
    final segments = uri?.pathSegments ?? [];
    if (segments.length >= 2) {
      kbRegistry = GithubReleasesKbRegistry(
        owner: segments[0],
        repo: segments[1],
      );
    } else {
      stderr.writeln(
        '[JankDoc] WARNING: --kb-registry "$kbRegistryUrl" is not a valid '
        'GitHub repo URL (expected https://github.com/<owner>/<repo>). '
        'Registry disabled.',
      );
    }
  }

  final kbManager = KbManager(
    loader: kbLoader,
    seeder: seeder,
    registry: kbRegistry,
    onBundleReloaded: (bundle) {
      // Re-seed the vector store from the new bundle's pre-computed embeddings.
      seeder.seedFromBundle(bundle).ignore();
    },
  );

  // Bundle-first KB load — falls back to KbSeeder if no bundle is cached.
  final kbResult = await kbManager.load();
  print('[JankDoc] KB source: $kbResult');
  kbManager.startHotReload();

  final validator = OutputValidator();
  final sessionRepo = SessionRepository();
  final telemetryQueue = TelemetryQueue();

  // Tracks session IDs that have already been persisted this daemon run.
  // Uses INSERT OR REPLACE in SQLite so restarts are safe, but we avoid
  // issuing a DB write on every single batch (500ms intervals).
  final _seenSessions = <String>{};

  final pipeline = DiagnosisPipeline(
    ruleEngine: ruleEngine,
    llmProvider: llmProvider,
    vectorStore: vectorStore,
    validator: validator,
    sessionRepo: sessionRepo,
  );

  // ── HTTP server ────────────────────────────────────────────────────────────
  final router = Router()
    ..get('/health', _health)
    ..get(
        '/info',
        (Request r) => _info(
              r,
              modelId: modelId,
              ollamaUrl: ollamaUrl,
              embedModelId: embedModelId,
              llmProvider: llmProvider,
              kbResult: kbResult,
              vectorStore: vectorStore,
              ruleCount: ruleProvider.rules.length,
            ))
    ..post(
        '/telemetry/batch',
        (Request r) =>
            _ingestBatch(r, telemetryQueue, sessionRepo, _seenSessions,
                recordSink: recordSink))
    ..get('/diagnoses/stream',
        (Request r) => _streamDiagnoses(r, pipeline, telemetryQueue))
    ..get('/sessions', (Request r) => _listSessions(r, sessionRepo))
    ..get('/sessions/<id>',
        (Request r, String id) => _getSession(r, id, sessionRepo))
    ..get('/kb/status', (Request r) => _kbStatus(r, vectorStore))
    ..post('/kb/reseed', (Request r) => _kbReseed(r, seeder))
    ..post('/kb/hot-reload', (Request r) => _kbHotReload(r, kbManager))
    ..get('/kb/check-update',
        (Request r) => _kbCheckUpdate(r, kbRegistry, kbManager));

  final handler = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final HttpServer server;
  try {
    server = await shelf_io.serve(handler, '127.0.0.1', port);
  } on SocketException catch (e) {
    // EADDRINUSE on macOS=48, Linux=98; check message for portability.
    if (e.message.contains('Address already in use') ||
        (e.osError?.errorCode == 48 || e.osError?.errorCode == 98)) {
      stderr.writeln(
        '[JankDoc] Port $port in use by another process (not JankDoc). '
        'Set JANKDOC_PORT env var to override.',
      );
      exit(1);
    }
    rethrow;
  }
  server.autoCompress = true;

  print('[JankDoc] daemon v1.0.0 listening on http://127.0.0.1:$port');
  print('[JankDoc] LLM: $modelId @ $ollamaUrl');
  print('[JankDoc] Embed: $embedModelId');
  print('[JankDoc] Rules: ${ruleProvider.rules.length} built-in');
  print(
      '[JankDoc] KB: $kbResult (${KbSeeder.catalogIds.length} catalog entries)');
  print(
      '[JankDoc] KB registry: ${kbRegistry != null ? kbRegistryUrl : "disabled"}');

  // ── Ollama reachability check ───────────────────────────────────────────────
  // Non-fatal: rule tier still works. But guide the user to a fix if Ollama
  // is not reachable at first daemon start.
  final ollamaReachable = await llmProvider.isAvailable();
  if (!ollamaReachable) {
    final path = writeSetupOllamaFile(
      modelId: modelId,
      embedModelId: embedModelId,
    );
    stderr.writeln(
      '[JankDoc] Ollama not reachable at $ollamaUrl. LLM tier disabled.'
      '${path != null ? '\n[JankDoc] See $path for setup instructions.' : ''}'
      '\n[JankDoc] Run `dart run jankdoc:doctor` for a full checkup.',
    );
  }

  // ── Graceful shutdown ──────────────────────────────────────────────────────
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n[JankDoc] shutting down...');
    kbManager.dispose();
    await server.close(force: false);
    await vectorStore.flush();
    sessionRepo.dispose();
    exit(0);
  });
}

// ─── Route handlers ───────────────────────────────────────────────────────────

Response _health(Request request) =>
    Response.ok('{"status":"ok"}', headers: _jsonHeaders);

Future<Response> _info(
  Request request, {
  required String modelId,
  required String ollamaUrl,
  required String embedModelId,
  required OllamaProvider llmProvider,
  required KbLoadResult kbResult,
  required InMemoryVectorStore vectorStore,
  required int ruleCount,
}) async {
  // Cheap availability probe — Ollama isAvailable() has a 2 s timeout and
  // handles throttled logging on failure.
  final llmAvailable = await llmProvider.isAvailable();
  final kbEntries = await vectorStore.count();
  return Response.ok(
    _encodeJson({
      'version': '1.0.0',
      'model': modelId,
      'embed_model': embedModelId,
      'ollama_url': ollamaUrl,
      'llm_available': llmAvailable,
      'kb_source': kbResult.source.name,
      'kb_version': kbResult.version?.toString(),
      'kb_entries': kbEntries,
      'rules': ruleCount,
    }),
    headers: _jsonHeaders,
  );
}

/// Receives a [TelemetryBatch] from the Flutter app.
///
/// On the first batch from a new sessionId, persists a [Session] row so
/// it appears in the sessions list and enables cross-session recurrence counts.
Future<Response> _ingestBatch(
  Request request,
  TelemetryQueue queue,
  SessionRepository sessionRepo,
  Set<String> seenSessions, {
  IOSink? recordSink,
}) async {
  final body = await request.readAsString();
  final decoded = _decodeJson(body);
  if (decoded == null) {
    return Response.badRequest(
      body: '{"error":"empty body"}',
      headers: _jsonHeaders,
    );
  }
  recordSink?.writeln(jsonEncode(decoded));

  final batch = TelemetryBatch.fromJson(decoded as Map<String, dynamic>);

  // ── Session creation (first batch per sessionId) ─────────────────────────
  // We upsert rather than insert-or-ignore so that startedAt is updated if
  // the same session ID is reused after a hot-restart (edge case).
  if (!seenSessions.contains(batch.sessionId)) {
    seenSessions.add(batch.sessionId);
    final session = Session(
      id: batch.sessionId,
      projectFingerprint: batch.projectFingerprint.isEmpty
          ? batch.sessionId // Fallback for old clients without fingerprint
          : batch.projectFingerprint,
      flutterVersion: batch.deviceInfo.flutterVersion,
      dartVersion: batch.deviceInfo.dartVersion,
      deviceInfo: batch.deviceInfo,
      startedAt: DateTime.fromMillisecondsSinceEpoch(batch.windowStartMs),
    );
    // Fire-and-forget — don't delay the response waiting for SQLite
    sessionRepo.saveSession(session).ignore();
  }

  queue.add(batch);
  return Response.ok('{"queued":true}', headers: _jsonHeaders);
}

Response _streamDiagnoses(
  Request request,
  DiagnosisPipeline pipeline,
  TelemetryQueue queue,
) {
  final stream = queue.batches
      .asyncExpand((batch) => pipeline.process(batch).handleError(
            (Object e, StackTrace st) =>
                stderr.writeln('[JankDoc] pipeline error: $e\n$st'),
          ))
      .map((d) => Uint8List.fromList(
            utf8.encode('data: ${_encodeJson(d.toJson())}\n\n'),
          ));

  return Response.ok(
    stream,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
      ..._corsHeaders,
    },
    context: {'shelf.io.buffer_output': false},
  );
}

Future<Response> _listSessions(
  Request request,
  SessionRepository repo,
) async {
  final sessions = await repo.listRecent(limit: 20);
  return Response.ok(
    _encodeJson({'sessions': sessions.map((s) => s.toJson()).toList()}),
    headers: _jsonHeaders,
  );
}

Future<Response> _getSession(
  Request request,
  String id,
  SessionRepository repo,
) async {
  final session = await repo.findById(id);
  if (session == null) {
    return Response.notFound(
      '{"error":"session not found"}',
      headers: _jsonHeaders,
    );
  }
  return Response.ok(_encodeJson(session.toJson()), headers: _jsonHeaders);
}

Future<Response> _kbStatus(
  Request request,
  InMemoryVectorStore store,
) async {
  final count = await store.count();
  return Response.ok(
    _encodeJson({
      'entries': count,
      'catalog_size': KbSeeder.catalogIds.length,
      'seeded': count >= KbSeeder.catalogIds.length,
    }),
    headers: _jsonHeaders,
  );
}

Future<Response> _kbReseed(
  Request request,
  KbSeeder seeder,
) async {
  // Run reseed in background — respond immediately so the client isn't blocked.
  seeder.reseed().ignore();
  return Response.ok(
    '{"reseeding":true}',
    headers: _jsonHeaders,
  );
}

Future<Response> _kbHotReload(
  Request request,
  KbManager manager,
) async {
  final result = await manager.load();
  return Response.ok(
    _encodeJson({'reloaded': true, 'source': result.source.name}),
    headers: _jsonHeaders,
  );
}

/// Manual trigger to check the remote registry for a newer KB bundle.
///
/// Returns whether an update was found and what the latest version is.
/// Called by the DevTools extension when the user clicks "Check for updates".
Future<Response> _kbCheckUpdate(
  Request request,
  GithubReleasesKbRegistry? registry,
  KbManager manager,
) async {
  if (registry == null) {
    return Response.ok(
      _encodeJson({
        'registry_enabled': false,
        'message': 'KB registry is disabled (--no-kb-registry).',
      }),
      headers: _jsonHeaders,
    );
  }

  try {
    final latest = await registry.latestVersion(KbChannel.stable);
    return Response.ok(
      _encodeJson({
        'registry_enabled': true,
        'latest_version': latest?.toString(),
        'has_update': latest != null,
      }),
      headers: _jsonHeaders,
    );
  } on KbRegistryException catch (e) {
    return Response.internalServerError(
      body: _encodeJson({'error': e.toString()}),
      headers: _jsonHeaders,
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _jsonHeaders = {
  'Content-Type': 'application/json',
};

// DevTools extensions run at a dynamic port — allow any localhost origin.
const _corsHeaders = {
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Map<String, String> _corsHeadersFor(Request request) {
  final origin = request.headers['origin'] ?? '*';
  return {
    'Access-Control-Allow-Origin': origin,
    ..._corsHeaders,
  };
}

Middleware _corsMiddleware() => (Handler inner) => (Request request) async {
      final cors = _corsHeadersFor(request);
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: cors);
      }
      final response = await inner(request);
      return response.change(headers: cors);
    };

dynamic _decodeJson(String s) => s.isEmpty ? null : jsonDecode(s);

String _encodeJson(Object? o) => jsonEncode(o);
