# LlmProvider is an interface; OllamaProvider is the default implementation

The analysis daemon calls into LLMs via an `LlmProvider` interface, not directly into the Ollama HTTP API. This decouples the business logic from the inference backend.

```dart
abstract interface class LlmProvider {
  Future<DiagnosisResult> diagnose(DiagnoseRequest request);
  Future<List<double>> embed(String text);
  Stream<String> diagnoseStream(DiagnoseRequest request);
}
```

Default implementation: `OllamaProvider` targeting `http://127.0.0.1:11434`. A second `OpenAiCompatibleProvider` covers LM Studio, vLLM, llama.cpp server, and OpenRouter — any OpenAI-compatible endpoint — without forking the core.

Model is configured in `jankdoc.yaml` at the Flutter project root, not hardcoded:

```yaml
jankdoc:
  llm:
    provider: ollama          # ollama | openai_compatible
    model: qwen2.5-coder:7b   # default
    base_url: http://127.0.0.1:11434
```

## Why this matters

Ollama is the default because it is free, local, and requires no API key. But enterprise teams on Windows with Copilot+ PCs may prefer llama.cpp server; teams with 16GB+ RAM may want Phi-4 14B via LM Studio. The interface ensures none of these are forks — they are configuration.

## Considered options

- **Hardcode Ollama** — eliminates the abstraction cost but creates a fork every time a user wants a different local backend. Already seeing this in the OSS ecosystem (tools that only support one local runtime fracture their communities).
- **Support cloud LLMs (OpenAI, Anthropic)** — valid as an opt-in BYO-key mode but must never be the default. The local-first guarantee is the trust moat.
