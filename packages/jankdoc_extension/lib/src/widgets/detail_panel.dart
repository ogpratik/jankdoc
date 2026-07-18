import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import '../providers/diagnosis_provider.dart';
import 'confidence_badge.dart';
import 'fix_panel.dart';

/// Right-hand detail panel that renders a full [Diagnosis].
///
/// Shows: severity header · root cause · explanation · fix · sources.
/// Scrollable; collapses cleanly to a selection prompt when nothing is selected.
class DetailPanel extends ConsumerWidget {
  const DetailPanel({super.key});

  static final _tsFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnosis = ref.watch(selectedDiagnosisProvider);
    final theme = Theme.of(context);

    if (diagnosis == null) {
      return _NothingSelected(theme);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          _DiagnosisHeader(diagnosis, theme),

          const SizedBox(height: 12),

          // ── Root cause ───────────────────────────────────────────────────
          _RootCauseSection(diagnosis, theme),

          const SizedBox(height: 4),

          // ── Explanation ──────────────────────────────────────────────────
          _ExplanationSection(diagnosis, theme),

          const SizedBox(height: 4),

          // ── Fix + sources ─────────────────────────────────────────────────
          FixPanel(
            fix: diagnosis.fix,
            sources: diagnosis.sources,
          ),

          // ── Footer metadata ───────────────────────────────────────────────
          _FooterMeta(diagnosis: diagnosis, theme: theme, tsFormat: _tsFormat),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Sub-sections ──────────────────────────────────────────────────────────────

class _DiagnosisHeader extends StatelessWidget {
  const _DiagnosisHeader(this.diagnosis, this.theme);
  final Diagnosis diagnosis;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final sevColor = _severityColor(diagnosis.severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: sevColor.withValues(alpha: isDark ? 0.08 : 0.05),
        border: Border(
          bottom: BorderSide(color: sevColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SeverityChip(diagnosis.severity),
              const SizedBox(width: 8),
              ConfidenceBadge(diagnosis.confidence),
              if (diagnosis.recurrenceCount > 1) ...[
                const SizedBox(width: 8),
                _RecurrenceBadge(diagnosis.recurrenceCount),
              ],
              const Spacer(),
              _TierIndicator(diagnosis.tier, theme),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _humanisePattern(diagnosis.patternId),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pattern: ${diagnosis.patternId}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  static String _humanisePattern(String id) {
    return id
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static Color _severityColor(Severity s) => switch (s) {
        Severity.critical => const Color(0xFFE53935),
        Severity.high => const Color(0xFFFF6D00),
        Severity.medium => const Color(0xFFFFB300),
        Severity.low => const Color(0xFF42A5F5),
      };
}

class _RootCauseSection extends StatelessWidget {
  const _RootCauseSection(this.diagnosis, this.theme);
  final Diagnosis diagnosis;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rc = diagnosis.rootCause;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROOT CAUSE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            rc.description,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),
          if (rc.file != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.code_outlined,
                    size: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      [
                        rc.file!,
                        if (rc.line != null) ':${rc.line}',
                        if (rc.column != null) ':${rc.column}',
                      ].join(),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (rc.widgetType != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        rc.widgetType!,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExplanationSection extends StatelessWidget {
  const _ExplanationSection(this.diagnosis, this.theme);
  final Diagnosis diagnosis;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXPLANATION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              diagnosis.explanation,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

class _FooterMeta extends StatelessWidget {
  const _FooterMeta({
    required this.diagnosis,
    required this.theme,
    required this.tsFormat,
  });
  final Diagnosis diagnosis;
  final ThemeData theme;
  final DateFormat tsFormat;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _MetaItem(
              label: 'ID',
              value: diagnosis.id.substring(0, 8),
              theme: theme,
            ),
            _MetaItem(
              label: 'Session',
              value: diagnosis.sessionId.substring(0, 8),
              theme: theme,
            ),
            _MetaItem(
              label: 'Frame',
              value: '${diagnosis.frameTsMs}ms',
              theme: theme,
            ),
            if (diagnosis.createdAt != null)
              _MetaItem(
                label: 'Time',
                value: tsFormat.format(diagnosis.createdAt!),
                theme: theme,
              ),
          ],
        ),
      );
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.label,
    required this.value,
    required this.theme,
  });
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      );
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected(this.theme);
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 36,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a diagnosis',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
}

// ── Shared internal chips ─────────────────────────────────────────────────────

class _SeverityChip extends StatelessWidget {
  const _SeverityChip(this.severity);
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final color = _color(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        severity.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static Color _color(Severity s) => switch (s) {
        Severity.critical => const Color(0xFFE53935),
        Severity.high => const Color(0xFFFF6D00),
        Severity.medium => const Color(0xFFFFB300),
        Severity.low => const Color(0xFF42A5F5),
      };
}

class _RecurrenceBadge extends StatelessWidget {
  const _RecurrenceBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEF9A9A).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.repeat, size: 10, color: Color(0xFFEF9A9A)),
            const SizedBox(width: 3),
            Text(
              'Seen ${count}x',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF9A9A),
              ),
            ),
          ],
        ),
      );
}

class _TierIndicator extends StatelessWidget {
  const _TierIndicator(this.tier, this.theme);
  final DiagnosisTier tier;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isRule = tier == DiagnosisTier.rule;
    return Tooltip(
      message: isRule
          ? 'Rule-tier: pattern matched deterministically, no LLM invoked'
          : 'LLM-tier: Ollama analysed the frame with RAG context',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRule ? Icons.rule_outlined : Icons.psychology_outlined,
            size: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 4),
          Text(
            isRule ? 'Rule-tier' : 'LLM-tier',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
