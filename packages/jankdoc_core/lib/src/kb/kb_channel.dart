/// The four KB promotion channels, ordered from least to most trusted.
enum KbChannel {
  /// Schema + citation only. Advisory CI. Never blocks. Opt-in via jankdoc.yaml.
  experimental,

  /// Threshold-based CI. Partially blocking. Opt-in via jankdoc.yaml.
  candidate,

  /// Full CI gate. Unconditionally blocking. Default for all users.
  stable,

  /// Machine-local entries under .jankdoc/local-kb/. No CI. Never shared.
  local;

  /// Whether this channel requires a public CI gate to accept an entry.
  bool get hasCiGate => this != local;

  /// Whether this channel's CI gate is unconditionally blocking on failure.
  bool get isBlockingCi => this == stable;

  /// A [local] bundle is the configured public channel + local entries.
  /// All other bundles are supersets of [stable].
  bool get isPublic => this != local;

  /// Returns true if this channel's bundle contains entries from [other].
  ///
  /// Bundle composition:
  ///   stable     → stable only
  ///   candidate  → stable + candidate
  ///   experimental → stable + candidate + experimental
  ///   local      → configured public channel + local entries (handled separately)
  bool includes(KbChannel other) {
    if (this == local) return other == local;
    return other.index >= stable.index && other.index <= index;
  }
}
