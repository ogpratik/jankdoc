import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:jankdoc_core/jankdoc_core.dart';

/// Discovers and downloads KB bundles from GitHub Releases.
///
/// Calls the GitHub REST API (`/repos/<owner>/<repo>/releases`) to list
/// releases, parses tag names as [KbVersion]s, filters by [KbChannel], and
/// downloads the `.jankdoc-kb` asset for the best matching version.
///
/// **Rate limiting**: GitHub's unauthenticated API allows 60 requests/hour
/// per IP. This class caches the latest-version lookup result for
/// [_cacheDuration] (default: 5 minutes) to stay well within that budget
/// even if the daemon polls aggressively.
///
/// **Authentication**: Pass a GitHub personal-access-token (or fine-grained
/// token) via [authToken] to raise the limit to 5 000 req/hr and to access
/// private repos.
final class GithubReleasesKbRegistry implements KbRegistry {
  GithubReleasesKbRegistry({
    String owner = 'ogpratik',
    String repo = 'jankdoc-kb',
    http.Client? httpClient,
    String? authToken,
    Duration cacheDuration = const Duration(minutes: 5),
  })  : _owner = owner,
        _repo = repo,
        _client = httpClient ?? http.Client(),
        _authToken = authToken,
        _cacheDuration = cacheDuration;

  final String _owner;
  final String _repo;
  final http.Client _client;
  final String? _authToken;
  final Duration _cacheDuration;

  // Per-channel version cache.
  final _cache = <KbChannel, _CacheEntry>{};

  // Exponential backoff state for rate-limit responses (403 / 429).
  // When non-null, all API calls are skipped until _rateLimitResetAt.
  DateTime? _rateLimitResetAt;
  int _rateLimitBackoffIndex = 0;

  // Doubles: 1 m, 2 m, 4 m, 8 m, 16 m, 30 m (capped).
  static const _kBackoff = [
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 4),
    Duration(minutes: 8),
    Duration(minutes: 16),
    Duration(minutes: 30),
  ];

  // ── KbRegistry ─────────────────────────────────────────────────────────────

  @override
  Future<KbVersion?> latestVersion(KbChannel channel) async {
    // Return cached result if still fresh.
    final cached = _cache[channel];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
      return cached.version;
    }

    final releases = await _fetchReleases();
    KbVersion? best;
    for (final release in releases) {
      final tag = release['tag_name'] as String? ?? '';
      if (!tag.startsWith('v')) continue;
      final versionStr = tag.substring(1); // strip leading 'v'

      final KbVersion version;
      try {
        version = KbVersion.parse(versionStr);
      } on Object {
        continue; // skip malformed tags
      }

      // Channel filtering: a release belongs to the channel its pre-release
      // suffix implies. Plain semver (no suffix) → stable.
      if (version.channel != channel) continue;

      // Skip pre-releases flagged as drafts.
      if (release['draft'] as bool? ?? false) continue;

      if (best == null || version.compareTo(best) > 0) {
        best = version;
      }
    }

    _cache[channel] = _CacheEntry(version: best, fetchedAt: DateTime.now());
    return best;
  }

  @override
  Future<Uint8List> download(KbVersion version) async {
    // First get the release to find the asset download URL.
    final tagName = 'v$version';
    final releases = await _fetchReleases();

    Map<String, dynamic>? targetRelease;
    for (final r in releases) {
      if (r['tag_name'] == tagName) {
        targetRelease = r;
        break;
      }
    }

    if (targetRelease == null) {
      throw KbRegistryException(
        'No release found for tag $tagName in $_owner/$_repo',
      );
    }

    // Find the .jankdoc-kb asset.
    final assets = (targetRelease['assets'] as List?) ?? [];
    final assetName = 'jankdoc-kb-$version.jankdoc-kb';
    Map<String, dynamic>? asset;
    for (final a in assets) {
      if ((a as Map<String, dynamic>)['name'] == assetName) {
        asset = a;
        break;
      }
    }

    if (asset == null) {
      throw KbRegistryException(
        'Release $tagName exists but has no asset named "$assetName". '
        'Assets found: ${assets.map((a) => (a as Map)['name']).toList()}',
      );
    }

    final downloadUrl = asset['browser_download_url'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw KbRegistryException(
        'Asset "$assetName" has no browser_download_url.',
      );
    }

    return _downloadBytes(downloadUrl);
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Fetch the list of releases from the GitHub API.
  ///
  /// Returns up to 100 releases (GitHub's max per page). For repos with more
  /// than 100 releases pagination would be needed — acceptable for beta.
  Future<List<Map<String, dynamic>>> _fetchReleases() async {
    // Honour rate-limit backoff: if we're still in a cooldown window, skip the
    // request entirely and re-throw so callers fall back to cached data.
    if (_rateLimitResetAt != null &&
        DateTime.now().isBefore(_rateLimitResetAt!)) {
      throw KbRegistryException(
        'GitHub API rate limit backoff active until '
        '${_rateLimitResetAt!.toIso8601String()}.',
        statusCode: 429,
      );
    }

    final uri = Uri.parse(
      'https://api.github.com/repos/$_owner/$_repo/releases?per_page=100',
    );

    final response = await _client.get(uri, headers: _headers()).timeout(
          const Duration(seconds: 10),
        );

    if (response.statusCode == 404) {
      throw KbRegistryException(
        'Repository $_owner/$_repo not found.',
        statusCode: 404,
      );
    }

    if (response.statusCode == 403 || response.statusCode == 429) {
      _applyRateLimitBackoff(response);
      throw KbRegistryException(
        'GitHub API rate limited for $_owner/$_repo.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      throw KbRegistryException(
        'GitHub API returned ${response.statusCode} for $_owner/$_repo/releases.',
        statusCode: response.statusCode,
      );
    }

    // Successful call — reset exponential backoff counter.
    _rateLimitBackoffIndex = 0;
    _rateLimitResetAt = null;

    final dynamic body = jsonDecode(response.body);
    if (body is! List) {
      throw const KbRegistryException(
        'GitHub releases response was not a JSON array.',
      );
    }
    return body.cast<Map<String, dynamic>>();
  }

  /// Record the rate-limit event, advance the backoff index, and log once.
  void _applyRateLimitBackoff(http.Response response) {
    final idx = _rateLimitBackoffIndex.clamp(0, _kBackoff.length - 1);
    var resetAt = DateTime.now().add(_kBackoff[idx]);

    // Prefer the header-provided reset time when it's sooner.
    final resetHeader = response.headers['x-ratelimit-reset'];
    if (resetHeader != null) {
      final headerReset = DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(resetHeader)! * 1000,
      );
      if (headerReset.isBefore(resetAt)) resetAt = headerReset;
    }

    _rateLimitResetAt = resetAt;
    if (_rateLimitBackoffIndex < _kBackoff.length - 1) {
      _rateLimitBackoffIndex++;
    }

    stderr.writeln(
      '[JankDoc/KbRegistry] GitHub API rate limited. '
      'Next attempt after ${resetAt.toIso8601String()} '
      '(backoff #$idx: ${_kBackoff[idx].inMinutes}m).',
    );
  }

  /// Download raw bytes from a URL, following redirects.
  Future<Uint8List> _downloadBytes(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: _headers())
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw KbRegistryException(
        'Failed to download asset from $url.',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  Map<String, String> _headers() => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };
}

// ── Cache types ────────────────────────────────────────────────────────────────

final class _CacheEntry {
  _CacheEntry({required this.version, required this.fetchedAt});

  final KbVersion? version;
  final DateTime fetchedAt;
}
