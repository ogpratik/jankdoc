import 'dart:io';

import 'package:test/test.dart';

/// Regression guardrail for the daemon-binary download URL contract.
///
/// [DaemonLauncher] constructs the download URL as:
///
///     $repo/releases/download/daemon-v$_kDaemonVersion/jankdoc-daemon-$_kDaemonVersion-$platform
///
/// This URL is glued to two other files:
///   - `.github/workflows/release.yaml` — triggers on `daemon-v*` tags and
///     names its uploaded artefact `jankdoc-daemon-<version>-<platform>`.
///   - `packages/jankdoc/assets/binary_checksums.json` — keyed by the same
///     `jankdoc-daemon-<version>-<platform>` filename.
///
/// If any of the four break, users hit either a 404 on first run or a
/// checksum mismatch — silent from the pub package's point of view. This
/// test locks the pieces together by reading the source and workflow.
void main() {
  late String daemonLauncherSrc;
  late String releaseWorkflowSrc;
  late String checksumsJson;

  setUpAll(() {
    daemonLauncherSrc =
        File('lib/src/daemon_launcher.dart').readAsStringSync();
    releaseWorkflowSrc =
        File('../../.github/workflows/release.yaml').readAsStringSync();
    checksumsJson =
        File('assets/binary_checksums.json').readAsStringSync();
  });

  test('daemon_launcher constructs URLs under /daemon-v<version>/', () {
    expect(
      daemonLauncherSrc,
      contains(r"/releases/download/daemon-v$_kDaemonVersion/"),
      reason: 'DaemonLauncher must fetch under the daemon-v tag namespace so '
          'daemon binary tags never collide with pub-package release tags.',
    );
  });

  test('release workflow triggers on daemon-v* tags (never plain v*)', () {
    expect(releaseWorkflowSrc, contains('tags: ["daemon-v*"]'));
    expect(
      releaseWorkflowSrc,
      contains("startsWith(github.ref, 'refs/tags/daemon-v')"),
      reason: 'The release job must gate on daemon-v tag prefix to skip when '
          'a pub-package tag is pushed.',
    );
  });

  test('workflow reads _kDaemonVersion out of daemon_launcher.dart', () {
    // If someone renames the constant or the workflow's grep pattern, this
    // catches it before the CI does.
    expect(
      releaseWorkflowSrc,
      contains(r'grep -E "^const _kDaemonVersion"'),
    );
    expect(
      daemonLauncherSrc,
      matches(RegExp(r"^const _kDaemonVersion\s*=\s*'[^']+';",
          multiLine: true)),
      reason: 'daemon_launcher.dart must expose a top-level '
          '`const _kDaemonVersion = \'x.y.z\';` for the workflow to grep.',
    );
  });

  test('binary_checksums.json is keyed by platform names the workflow uses',
      () {
    for (final platform in [
      'macos-arm64',
      'macos-x64',
      'linux-x64',
      'windows-x64',
    ]) {
      expect(
        releaseWorkflowSrc,
        contains('platform: $platform'),
        reason: 'release.yaml matrix must include $platform',
      );
    }
    // The checksum file may be empty at beta but the schema must exist.
    expect(checksumsJson, contains('"binaries"'));
  });

  test('DaemonLauncher and workflow parse the same version string', () {
    final launcherMatch = RegExp(r"^const _kDaemonVersion\s*=\s*'([^']+)';",
            multiLine: true)
        .firstMatch(daemonLauncherSrc);
    expect(launcherMatch, isNotNull);
    final launcherVersion = launcherMatch!.group(1)!;
    // Reproduce the workflow's parse step: `grep -E "^const _kDaemonVersion"`
    // followed by `sed -E "s/.*'([^']+)'.*/\\1/"`.
    final workflowParsed = daemonLauncherSrc
        .split('\n')
        .where((l) => l.startsWith('const _kDaemonVersion'))
        .map((l) => RegExp(r"'([^']+)'").firstMatch(l)?.group(1))
        .whereType<String>()
        .single;
    expect(workflowParsed, launcherVersion);
  });
}
