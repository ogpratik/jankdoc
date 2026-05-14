# DevTools extension uses Riverpod for state management

The `jankdoc_extension` Flutter web app uses Riverpod (flutter_riverpod) for all state management.

## Why Riverpod

- **No BuildContext dependency** — providers are accessed without context, which matters in a DevTools extension where the widget tree is shallow and lifecycle events come from external sources (daemon SSE stream, VM Service events).
- **Testable in isolation** — `ProviderContainer` allows unit-testing state logic without a widget tree. This is essential for the eval harness asserting on extension behaviour.
- **Compile-time safety** — `@riverpod` code generation eliminates the stringly-typed provider lookup that causes runtime errors in production Provider/GetX.
- **StreamProvider** handles the SSE diagnosis stream natively with automatic lifecycle management (subscribe on first listener, cancel on last).

## Key providers

```dart
@riverpod
Stream<Diagnosis> diagnosisStream(DiagnosisStreamRef ref) =>
    ref.watch(daemonClientProvider).diagnoses();

@riverpod
class SessionState extends _$SessionState { ... }

@riverpod
DaemonClient daemonClient(DaemonClientRef ref) =>
    DaemonClient(baseUrl: ref.watch(daemonUrlProvider));
```

## Considered options

- **BLoC** — correct for complex event-driven flows; overkill for a DevTools extension with a simple unidirectional data flow (daemon → extension → render).
- **Provider (flutter_provider)** — deprecated direction; Riverpod is its successor from the same author.
- **setState** — not viable beyond trivial widgets.
