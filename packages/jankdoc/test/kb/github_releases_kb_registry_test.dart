import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

import '../../lib/src/kb/github_releases_kb_registry.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a fake GitHub releases API response.
///
/// [tags] is a list of tag name strings, e.g. ['v1.1.0', 'v1.0.0'].
/// [draftTag] (if set) marks that release as a draft.
String _releasesJson(
  List<String> tags, {
  String? draftTag,
  Map<String, String> assetsByTag = const {},
}) {
  final releases = tags.map((tag) {
    final assetName = assetsByTag[tag];
    return {
      'tag_name': tag,
      'draft': tag == draftTag,
      'prerelease': false,
      'assets': assetName == null
          ? <Map<String, Object?>>[]
          : [
              {
                'name': assetName,
                'browser_download_url':
                    'https://example.com/releases/download/$tag/$assetName',
              }
            ],
    };
  }).toList();
  return jsonEncode(releases);
}

/// A fake minimal .jankdoc-kb bundle for download tests.
final _fakeBundleBytes = Uint8List.fromList(utf8.encode('fake-bundle'));

GithubReleasesKbRegistry _registry(MockClient client) =>
    GithubReleasesKbRegistry(
      owner: 'test-owner',
      repo: 'test-repo',
      httpClient: client,
      // Very short cache so tests don't interfere.
      cacheDuration: Duration.zero,
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('GithubReleasesKbRegistry.latestVersion', () {
    test('returns highest stable version from releases list', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/releases'));
        return http.Response(
          _releasesJson(['v1.2.0', 'v1.1.0', 'v1.0.0']),
          200,
        );
      });

      final registry = _registry(client);
      final version = await registry.latestVersion(KbChannel.stable);
      expect(version, isNotNull);
      expect(version.toString(), equals('1.2.0'));
    });

    test('returns highest candidate version, ignores stable releases', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson([
              'v2.0.0-candidate.3',
              'v2.0.0-candidate.1',
              'v1.9.0', // stable — must be ignored
            ]),
            200,
          ));

      final registry = _registry(client);
      final version = await registry.latestVersion(KbChannel.candidate);
      expect(version?.toString(), equals('2.0.0-candidate.3'));
    });

    test('returns null when no matching channel releases exist', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson(['v1.0.0', 'v1.1.0']), // all stable
            200,
          ));

      final registry = _registry(client);
      final version = await registry.latestVersion(KbChannel.candidate);
      expect(version, isNull);
    });

    test('skips draft releases', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson(
              ['v1.2.0', 'v1.1.0'],
              draftTag: 'v1.2.0', // newest is draft
            ),
            200,
          ));

      final registry = _registry(client);
      final version = await registry.latestVersion(KbChannel.stable);
      expect(version?.toString(), equals('1.1.0'));
    });

    test('skips malformed tag names', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson(['not-a-semver', 'v1.0.0', 'vbanana']),
            200,
          ));

      final registry = _registry(client);
      final version = await registry.latestVersion(KbChannel.stable);
      expect(version?.toString(), equals('1.0.0'));
    });

    test('throws KbRegistryException on 404', () async {
      final client =
          MockClient((_) async => http.Response('{"message":"Not Found"}', 404));

      final registry = _registry(client);
      expect(
        () => registry.latestVersion(KbChannel.stable),
        throwsA(
          isA<KbRegistryException>()
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('throws KbRegistryException on 403 rate limit', () async {
      final client = MockClient((_) async => http.Response(
            '{"message":"API rate limit exceeded"}',
            403,
            headers: {'x-ratelimit-reset': '9999999999'},
          ));

      final registry = _registry(client);
      expect(
        () => registry.latestVersion(KbChannel.stable),
        throwsA(
          isA<KbRegistryException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('rate limit')),
        ),
      );
    });

    test('throws KbRegistryException on 429 rate limit', () async {
      final client =
          MockClient((_) async => http.Response('{"message":"too many requests"}', 429));

      final registry = _registry(client);
      expect(
        () => registry.latestVersion(KbChannel.stable),
        throwsA(isA<KbRegistryException>()),
      );
    });

    test('throws KbRegistryException when response is not a JSON array', () async {
      final client = MockClient(
          (_) async => http.Response('{"unexpected":"object"}', 200));

      final registry = _registry(client);
      expect(
        () => registry.latestVersion(KbChannel.stable),
        throwsA(isA<KbRegistryException>()),
      );
    });

    test('caches result within cacheDuration', () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        return http.Response(_releasesJson(['v1.0.0']), 200);
      });

      final registry = GithubReleasesKbRegistry(
        owner: 'test-owner',
        repo: 'test-repo',
        httpClient: client,
        cacheDuration: const Duration(seconds: 60), // long cache
      );

      await registry.latestVersion(KbChannel.stable);
      await registry.latestVersion(KbChannel.stable);
      await registry.latestVersion(KbChannel.stable);

      expect(callCount, equals(1), reason: 'Should only hit API once within cache window');
    });
  });

  // ── download ───────────────────────────────────────────────────────────────

  group('GithubReleasesKbRegistry.download', () {
    test('downloads asset bytes for a known version', () async {
      final version = KbVersion.stable(1, 0, 0);
      final assetName = 'jankdoc-kb-1.0.0.jankdoc-kb';

      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            _releasesJson(
              ['v1.0.0'],
              assetsByTag: {'v1.0.0': assetName},
            ),
            200,
          );
        }
        // Asset download request.
        return http.Response.bytes(_fakeBundleBytes, 200);
      });

      final registry = _registry(client);
      final bytes = await registry.download(version);
      expect(bytes, equals(_fakeBundleBytes));
    });

    test('throws KbRegistryException when release not found', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson(['v0.9.0']), // no v1.0.0
            200,
          ));

      final registry = _registry(client);
      expect(
        () => registry.download(KbVersion.stable(1, 0, 0)),
        throwsA(
          isA<KbRegistryException>()
              .having((e) => e.message, 'message', contains('No release')),
        ),
      );
    });

    test('throws KbRegistryException when asset not found in release', () async {
      final client = MockClient((_) async => http.Response(
            _releasesJson(['v1.0.0']), // release exists, no assets
            200,
          ));

      final registry = _registry(client);
      expect(
        () => registry.download(KbVersion.stable(1, 0, 0)),
        throwsA(
          isA<KbRegistryException>()
              .having((e) => e.message, 'message', contains('no asset')),
        ),
      );
    });

    test('throws KbRegistryException on non-200 asset download', () async {
      final version = KbVersion.stable(1, 0, 0);
      final assetName = 'jankdoc-kb-1.0.0.jankdoc-kb';

      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            _releasesJson(
              ['v1.0.0'],
              assetsByTag: {'v1.0.0': assetName},
            ),
            200,
          );
        }
        return http.Response('Gone', 410);
      });

      final registry = _registry(client);
      expect(
        () => registry.download(version),
        throwsA(
          isA<KbRegistryException>()
              .having((e) => e.statusCode, 'statusCode', 410),
        ),
      );
    });
  });

  // ── KbRegistryException ────────────────────────────────────────────────────

  group('KbRegistryException', () {
    test('toString includes message', () {
      const e = KbRegistryException('test error');
      expect(e.toString(), contains('test error'));
    });

    test('toString includes statusCode when present', () {
      const e = KbRegistryException('rate limited', statusCode: 429);
      expect(e.toString(), contains('HTTP 429'));
    });

    test('toString includes cause when present', () {
      final cause = Exception('network unreachable');
      final e = KbRegistryException('failed', cause: cause);
      expect(e.toString(), contains('network unreachable'));
    });
  });
}
