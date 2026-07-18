import 'dart:io';

/// Writes `~/.jankdoc/setup-ollama.md` with platform-specific install
/// instructions, and returns its path so the caller can log it.
///
/// Called from the daemon on startup when [OllamaProvider.isAvailable] returns
/// false, and by `dart run jankdoc:doctor`. The file is idempotent — safe to
/// overwrite on every daemon start.
///
/// Returns null if the home directory cannot be resolved.
String? writeSetupOllamaFile({
  String? homeOverride,
  String modelId = 'qwen2.5-coder:7b',
  String embedModelId = 'nomic-embed-text',
}) {
  final home = homeOverride ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null) return null;

  final dir = Directory('$home/.jankdoc');
  dir.createSync(recursive: true);
  final path = '${dir.path}/setup-ollama.md';

  final os = Platform.operatingSystem;
  final installCmd = switch (os) {
    'macos' => 'brew install ollama  # or download from https://ollama.com',
    'linux' => 'curl -fsSL https://ollama.com/install.sh | sh',
    'windows' => 'winget install Ollama.Ollama  '
        '# or download from https://ollama.com',
    _ => 'See https://ollama.com for install instructions',
  };
  final serveCmd = os == 'macos'
      ? 'open -a Ollama  # (or `ollama serve` in a terminal)'
      : 'ollama serve';

  File(path).writeAsStringSync('''
# Setting up Ollama for JankDoc

JankDoc's LLM tier needs [Ollama](https://ollama.com) running locally with two models
pulled. Without Ollama, the rule tier still works — you'll just miss the LLM-generated
diagnoses for novel jank patterns.

## 1. Install Ollama

```
$installCmd
```

## 2. Start Ollama

```
$serveCmd
```

Ollama listens on `http://127.0.0.1:11434` by default. Confirm it's running:

```
curl http://127.0.0.1:11434/api/tags
```

## 3. Pull the models JankDoc uses

```
ollama pull $modelId       # LLM tier
ollama pull $embedModelId   # KB embedding
```

Total download: ~5 GB.

## 4. Verify

```
dart run jankdoc:doctor
```

You should see green ✓ on all four Ollama checks.

## Troubleshooting

- **Port 11434 in use** — change with `OLLAMA_HOST=127.0.0.1:11500 ollama serve`,
  then start the daemon with `--ollama-url http://127.0.0.1:11500`.
- **Model too large for your GPU** — use `qwen2.5-coder:3b` (edit
  `--model` in your daemon args, and re-pull).
- **Still stuck** — file an issue at https://github.com/ogpratik/jankdoc
''');

  return path;
}
