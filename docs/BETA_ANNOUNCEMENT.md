# JankDoc public beta

**A Flutter DevTools extension that tells you exactly what's causing jank.
Local AI. Zero data egress.**

Every Flutter developer has stared at a scroll timeline in DevTools trying to
figure out which widget is spinning up the raster thread. JankDoc watches the
same frame-timing feed and turns it into structured diagnoses — file, line,
widget, fix, and confidence.

## What you get in beta.1

- **One-line install.** Add `jankdoc: ^1.0.0-beta.1` to your dev deps, put
  `await JankDoc.attach();` before `runApp()`, done.
- **Two-tier diagnosis.** A rule pre-filter catches 26 common antipatterns
  in under 5 ms (no LLM needed). Anything a rule doesn't match falls through
  to a local Ollama model, grounded in a versioned knowledge base.
- **Zero data egress.** Everything runs on `127.0.0.1`. Only the KB bundle
  and daemon binary are ever fetched from the internet — both from public
  GitHub Releases, SHA-256 verified, and disable-able.
- **Colour-coded startup banner.** You know within two seconds of `flutter
  run` whether the LLM tier is up, which KB you're on, and how to fix it if
  something's off.
- **`dart run jankdoc:doctor`.** Health check + copy-pasteable fix hints.
  Exit code 1 on any fail — safe to gate CI on.
- **SARIF for CI.** `dart run jankdoc:ci` emits SARIF 2.1.0. GitHub renders
  it as Code Scanning alerts on the PR diff.

## Try it in 30 seconds

```yaml
# pubspec.yaml
dev_dependencies:
  jankdoc: ^1.0.0-beta.1
```

```dart
// lib/main.dart
import 'package:jankdoc/jankdoc.dart';

void main() async {
  await JankDoc.attach();
  runApp(const MyApp());
}
```

```bash
flutter run
# Open DevTools → JankDoc tab.
```

Or clone the sample:

```bash
git clone https://github.com/ogpratik/jankdoc
cd jankdoc/examples/sample_app && flutter run
```

Three intentional jank screens (rebuild storm, `setState` in `build`,
`Opacity` overdraw) — each fires the corresponding rule.

## What we want to know

This is a public beta because we need to hear how it handles jank we haven't
seen. The feedback thread is here: **<https://github.com/ogpratik/jankdoc/issues/1>**

Specific things to try:

1. Run it against your actual app.
2. Run `dart run jankdoc:doctor` and share the output if anything's wrong.
3. Look at the diagnoses it produces — are they specific enough to act on?
   File false-positives against
   `https://github.com/ogpratik/jankdoc/issues/new` with the telemetry batch
   from `~/.jankdoc/sessions.db`.

## What's not in beta

- Windows daemon binary — Windows users currently get the `dart run`
  fallback path (~5 s slower cold start).
- LLM accuracy baseline on novel jank patterns — Phase 2.3 of the launch
  plan; will be published as `docs/llm-baseline.md` before 1.0 stable.
- The KB bundle is small (~26 entries). Contributions welcome at
  <https://github.com/ogpratik/jankdoc-kb>.

## Links

- Source & issues: <https://github.com/ogpratik/jankdoc>
- pub.dev: <https://pub.dev/packages/jankdoc>
- KB contributor repo: <https://github.com/ogpratik/jankdoc-kb>
- Beta feedback thread: <https://github.com/ogpratik/jankdoc/issues/1>

MIT license. Built by [Pratik Pandey](https://github.com/ogpratik).
