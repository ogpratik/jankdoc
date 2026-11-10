# Notes for AI coding agents

This project uses **JankDoc** (`jankdoc_lints` analyzer plugin) to catch
Flutter code that causes jank.

- After editing Dart files, run `dart analyze` (not `flutter analyze`, which
  does not wait for analyzer-plugin results) and fix every
  `jankdoc_lints/*` warning before finishing.
- Each warning's correction message says what to change; the KB id in
  parentheses (e.g. `setstate-in-build`) names the pattern.
- `dart run ../../packages/jankdoc_lints/bin/jankdoc_check.dart` prints only
  JankDoc findings and exits 1 if there are any.
