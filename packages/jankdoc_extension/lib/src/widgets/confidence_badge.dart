import 'package:flutter/material.dart';

/// A compact pill that shows confidence as a percentage.
///
/// Colour semantics:
///   ≥90%  → green   (high trust, rule-tier attribution)
///   75–89% → amber  (moderate trust)
///   <75%  → orange  (low trust — LLM citation unverified)
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge(
    this.confidence, {
    super.key,
    this.compact = false,
  });

  /// Value in [0.0, 1.0].
  final double confidence;

  /// When true renders only the percentage without the "confidence" label.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    final color = _colorFor(confidence);
    final label = compact ? '$pct%' : '$pct% confidence';

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static Color _colorFor(double c) {
    if (c >= 0.90) return const Color(0xFF4CAF50); // green
    if (c >= 0.75) return const Color(0xFFFFB300); // amber
    return const Color(0xFFFF7043); // deep-orange
  }
}
