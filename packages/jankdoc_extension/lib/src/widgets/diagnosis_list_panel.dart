import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import '../providers/diagnosis_provider.dart';
import 'diagnosis_card.dart';
import 'empty_state.dart';

/// Left-hand panel: filter bar + scrollable [DiagnosisCard] list.
///
/// Animates new entries in from the top with a brief highlight.
class DiagnosisListPanel extends ConsumerWidget {
  const DiagnosisListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnoses = ref.watch(filteredDiagnosesProvider);
    final selected = ref.watch(selectedDiagnosisProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        _FilterBar(theme: theme),
        Expanded(
          child: diagnoses.isEmpty
              ? const EmptyState()
              : ListView.builder(
                  itemCount: diagnoses.length,
                  itemBuilder: (context, index) {
                    final d = diagnoses[index];
                    return _AnimatedEntry(
                      key: ValueKey(d.id),
                      child: DiagnosisCard(
                        diagnosis: d,
                        isSelected: selected?.id == d.id,
                        onTap: () => ref
                            .read(selectedDiagnosisProvider.notifier)
                            .state = d,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(diagnosisFilterProvider);
    final stats = ref.watch(diagnosisStatsProvider);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF252526)
            : const Color(0xFFFAFAFA),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF333333)
                : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in DiagnosisFilter.values)
                    _FilterChip(
                      filter: filter,
                      isActive: current == filter,
                      count: _countFor(filter, stats),
                      onTap: () => ref
                          .read(diagnosisFilterProvider.notifier)
                          .state = filter,
                      theme: theme,
                    ),
                ],
              ),
            ),
          ),
          if (stats.total > 0)
            IconButton(
              tooltip: 'Clear all diagnoses',
              icon: const Icon(Icons.clear_all, size: 16),
              onPressed: () {
                ref.read(diagnosisNotifierProvider.notifier).clear();
                ref.read(selectedDiagnosisProvider.notifier).state = null;
              },
              color: theme.colorScheme.onSurface.withOpacity(0.4),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  static int? _countFor(DiagnosisFilter filter, DiagnosisStats stats) =>
      switch (filter) {
        DiagnosisFilter.all => stats.total > 0 ? stats.total : null,
        DiagnosisFilter.rule => stats.ruleTier > 0 ? stats.ruleTier : null,
        DiagnosisFilter.llm => stats.llmTier > 0 ? stats.llmTier : null,
        DiagnosisFilter.critical =>
          stats.critical > 0 ? stats.critical : null,
      };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.isActive,
    required this.count,
    required this.onTap,
    required this.theme,
  });

  final DiagnosisFilter filter;
  final bool isActive;
  final int? count;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary.withOpacity(0.2)
                      : theme.colorScheme.onSurface.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Entry animation ───────────────────────────────────────────────────────────

/// Slides + fades in new diagnosis rows from the top.
class _AnimatedEntry extends StatefulWidget {
  const _AnimatedEntry({super.key, required this.child});
  final Widget child;

  @override
  State<_AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<_AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
