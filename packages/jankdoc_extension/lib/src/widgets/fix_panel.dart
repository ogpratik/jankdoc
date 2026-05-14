import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

/// Displays the [Fix] from a [Diagnosis]: summary, expected improvement,
/// optional before/after code diff, and sources list.
class FixPanel extends StatefulWidget {
  const FixPanel({
    super.key,
    required this.fix,
    required this.sources,
  });

  final Fix fix;
  final List<String> sources;

  @override
  State<FixPanel> createState() => _FixPanelState();
}

class _FixPanelState extends State<FixPanel>
    with SingleTickerProviderStateMixin {
  bool _showBefore = false; // default: show "after" (the solution)

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fix = widget.fix;
    final hasCode = fix.codeAfter != null || fix.codeBefore != null;
    final improvement = fix.expectedImprovementMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary ──────────────────────────────────────────────────────────
        _SectionHeader('Fix', theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  fix.summary,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ImprovementBadge(improvement),
            ],
          ),
        ),

        if (fix.dartFixCommand != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CommandChip(fix.dartFixCommand!, theme, isDark),
          ),
          const SizedBox(height: 8),
        ],

        // ── Code diff ────────────────────────────────────────────────────────
        if (hasCode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _TabButton(
                  label: 'After fix',
                  active: !_showBefore,
                  color: const Color(0xFF4CAF50),
                  onTap: () => setState(() => _showBefore = false),
                  theme: theme,
                ),
                const SizedBox(width: 4),
                if (fix.codeBefore != null)
                  _TabButton(
                    label: 'Before',
                    active: _showBefore,
                    color: const Color(0xFFE53935),
                    onTap: () => setState(() => _showBefore = true),
                    theme: theme,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CodeBlock(
              code: (_showBefore ? fix.codeBefore : fix.codeAfter) ?? '',
              isAfter: !_showBefore,
              isDark: isDark,
              theme: theme,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Sources ──────────────────────────────────────────────────────────
        if (widget.sources.isNotEmpty) ...[
          _SectionHeader('Sources', theme),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.sources
                  .map((url) => _SourceLink(url: url, theme: theme))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.theme);
  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.5),
          ),
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.5),
          ),
        ),
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }
}

class _ImprovementBadge extends StatelessWidget {
  const _ImprovementBadge(this.improvement);
  final (double min, double max) improvement;

  @override
  Widget build(BuildContext context) {
    final (min, max) = improvement;
    final label = min == max
        ? '~${min.toStringAsFixed(0)}ms'
        : '${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)}ms';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF4CAF50).withOpacity(0.4),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          const Text(
            '▲ SAVES',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4CAF50),
              letterSpacing: 0.8,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4CAF50),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip(this.command, this.theme, this.isDark);
  final String command;
  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            size: 12,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              command,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: command)),
            child: Icon(
              Icons.copy_outlined,
              size: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? color.withOpacity(0.5) : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? color
                : theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.code,
    required this.isAfter,
    required this.isDark,
    required this.theme,
  });

  final String code;
  final bool isAfter;
  final bool isDark;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isAfter
        ? const Color(0xFF4CAF50).withOpacity(0.3)
        : const Color(0xFFE53935).withOpacity(0.3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface.withOpacity(0.88),
                height: 1.5,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: code)),
              child: Tooltip(
                message: 'Copy',
                child: Icon(
                  Icons.copy_outlined,
                  size: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.url, required this.theme});
  final String url;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.open_in_new,
            size: 11,
            color: theme.colorScheme.primary.withOpacity(0.7),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: SelectableText(
              url,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
