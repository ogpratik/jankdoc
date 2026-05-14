/// JankDoc Analysis Daemon entry point.
///
/// Compiled to a native binary: `dart compile exe bin/daemon.dart`
/// Started automatically by JankDoc.attach() or the VS Code companion extension.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_rules/jankdoc_rules.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/src/analysis/diagnosis_pipeline.dart';
import '../lib/src/analysis/ollama_provider.dart';
import '../lib/src/analysis/output_validator.dart';
import '../lib/src/analysis/vector_store_impl.dart';
import '../lib/src/kb/kb_seeder.dart';
import '../lib/src/session/session_repository.dart';
import '../lib/src/telemetry/telemetry_queue.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '9101')
    ..addOption('ollama-url', defaultsTo: 'http://127.0.0.1:11434')
    ..addOption('model', defaultsTo: 'qwen2.5-coder:7b')
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('JankDoc Analysis Daemon\n${parser.usage}');
    exit(0);
  }

  final port = int.parse(results['port'] as String);
  final ollamaUrl = results['ollama-url'] as String;
  final modelId = results['model'] as String;

  // ── Dependency wiring ────────────────────────────────────────────────────
  final ruleProvider = BuiltInRuleProvider();
  final ruleEngine = RuleEngine(ruleProvider);
  final vectorStore = InMemoryVectorStore();
  await vectorStore.load(); // loads persisted embeddings from ~/.jankdoc/

  final llmProvider = OllamaProvider(
    baseUrl: ollamaUrl,
    modelId: modelId,
  );

  // Seed KB in the background — daemon starts serving immediately.
  // Seeding is idempotent: skipped if the store already has all entries.
  final seeder = KbSeeder(vectorStore: vectorStore, llmProvider: llmProvider);
  seeder.seed().ignore(); // non-blocking; LLM tier degrades gracefully if empty

  final validator = OutputValidator();
  final sessionRepo = SessionRepository();
  final telemetryQueue = TelemetryQueue();

  final pipeline = DiagnosisPipeline(
    ruleEngine: ruleEngine,
    llmProvider: llmProvider,
    vectorStore: vectorStore,
    validator: validator,
    sessionRepo: sessionRepo,
  );

  // ── HTTP server ──────────────────────────────────────────────────────────
  final router = Router()
    ..get('/health', _health)
    ..get('/info', (Request r) => _info(r, modelId, ollamaUrl))
    ..post('/telemetry/batch', (Request r) => _ingestBatch(r, telemetryQueue))
    ..get('/diagnoses/stream', (Request r) => _streamDiagnoses(r, pipeline, telemetryQueue))
    ..get('/sessions', (Request r) => _listSessions(r, sessionRepo))
    ..get('/sessions/<id>', (Request r, String id) => _getSession(r, id, sessionRepo))
    ..get('/kb/status', (Request r) => _kbStatus(r, vectorStore))
    ..post('/kb/reseed', (Request r) => _kbReseed(r, seeder));

  final handler = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, '127.0.0.1', port);
  server.autoCompress = true;

  print('[JankDoc] daemon v1.0.0 listening on http://127.0.0.1:$port');
  print('[JankDoc] LLM: $modelId @ $ollamaUrl');
  print('[JankDoc] Rules: ${ruleProvider.rules.length} built-in');
  print('[JankDoc] KB catalog: ${KbSeeder.catalogIds.length} entries (seeding async)');

  // ── Graceful shutdown ────────────────────────────────────────────────────
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n[JankDoc] shutting down...');
    await server.close(force: false);
    await vectorStore.flush();
    exit(0);
  });
}

// ─── Route handlers ──────────────────────────────────────────────────────────

Response _health(Request request) =>
    Response.ok('{"status":"ok"}', headers: _jsonHeaders);

Response _info(Request request, String modelId, String ollamaUrl) =>
    Response.ok(
      '{"version":"1.0.0","model":"$modelId","ollama_url":"$ollamaUrl"}',
      headers: _jsonHeaders,
    );

Future<Response> _ingestBatch(
  Request request,
  TelemetryQueue queue,
) async {
  final body = await request.readAsString();
  final decoded = _decodeJson(body);
  if (decoded == null) {
    return Response.badRequest(
      body: '{"error":"empty body"}',
      headers: _jsonHeaders,
    );
  }
  final batch = TelemetryBatch.fromJson(decoded as Map<String, dynamic>);
  queue.add(batch);
  return Response.ok('{"queued":true}', headers: _jsonHeaders);
}

Response _streamDiagnoses(
  Request request,
  DiagnosisPipeline pipeline,
  TelemetryQueue queue,
) {
  final stream = queue.batches
      .asyncExpand(pipeline.process)
      .map((d) => 'data: ${_encodeJson(d.toJson())}\n\n');

  return Response.ok(
    stream,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
      ..._corsHeaders,
    },
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
    return Response.notFound('{"error":"session not found"}',
        headers: _jsonHeaders);
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _jsonHeaders = {
  'Content-Type': 'application/json',
  ..._corsHeaders,
};

const _corsHeaders = {
  'Access-Control-Allow-Origin': 'http://127.0.0.1:9100',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Middleware _corsMiddleware() => (Handler inner) => (Request request) {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      return inner(request);
    };

dynamic _decodeJson(String s) => s.isEmpty ? null : jsonDecode(s);

String _encodeJson(Object? o) => jsonEncode(o);
