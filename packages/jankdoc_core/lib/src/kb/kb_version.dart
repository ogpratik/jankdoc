import 'package:pub_semver/pub_semver.dart';

import 'kb_channel.dart';

/// A semver version for the Knowledge Base, independent of the jankdoc package version.
///
/// Version format per channel:
///   stable:       2.1.0
///   candidate:    2.1.0-candidate.4
///   experimental: 2.1.0-exp.17
///   local:        (no version — loaded from disk at daemon startup)
final class KbVersion implements Comparable<KbVersion> {
  KbVersion._(this._version, this.channel);

  /// Parse a KB version string. The channel is inferred from the pre-release tag.
  factory KbVersion.parse(String version) {
    final v = Version.parse(version);
    final channel = _channelFromPreRelease(v.preRelease);
    return KbVersion._(v, channel);
  }

  /// Construct a stable KB version (no pre-release tag).
  factory KbVersion.stable(int major, int minor, int patch) =>
      KbVersion._(Version(major, minor, patch), KbChannel.stable);

  /// Construct a candidate KB version. [build] is the monotonic build counter.
  factory KbVersion.candidate(int major, int minor, int patch, int build) =>
      KbVersion._(
        Version(major, minor, patch, pre: 'candidate.$build'),
        KbChannel.candidate,
      );

  /// Construct an experimental KB version. [build] is the monotonic build counter.
  factory KbVersion.experimental(int major, int minor, int patch, int build) =>
      KbVersion._(
        Version(major, minor, patch, pre: 'exp.$build'),
        KbChannel.experimental,
      );

  static KbChannel _channelFromPreRelease(List<Object> preRelease) {
    if (preRelease.isEmpty) return KbChannel.stable;
    final tag = preRelease.first.toString();
    if (tag == 'candidate') return KbChannel.candidate;
    if (tag == 'exp') return KbChannel.experimental;
    return KbChannel.stable;
  }

  final Version _version;
  final KbChannel channel;

  int get major => _version.major;
  int get minor => _version.minor;
  int get patch => _version.patch;

  /// Whether this version satisfies [constraint] (pub_semver VersionConstraint).
  bool satisfies(VersionConstraint constraint) => constraint.allows(_version);

  @override
  int compareTo(KbVersion other) => _version.compareTo(other._version);

  bool operator >(KbVersion other) => compareTo(other) > 0;
  bool operator >=(KbVersion other) => compareTo(other) >= 0;
  bool operator <(KbVersion other) => compareTo(other) < 0;
  bool operator <=(KbVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is KbVersion && _version == other._version;

  @override
  int get hashCode => _version.hashCode;

  @override
  String toString() => _version.toString();
}
