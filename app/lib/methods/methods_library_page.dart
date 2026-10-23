import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../home/home_page.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'method_page.dart';

/// Methods library screen: browsable catalog of piano methods outside the main course.
class MethodsLibraryPage extends StatefulWidget {
  const MethodsLibraryPage({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId) onPlay;

  @override
  State<MethodsLibraryPage> createState() => _MethodsLibraryPageState();
}

class _MethodsLibraryPageState extends State<MethodsLibraryPage> {
  String? _selectedLevel;
  String? _selectedSkill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = widget.repo;
    final progress = widget.progress;

    final filteredMethods = repo.methods.where((m) {
      if (_selectedLevel != null && !m.levels.contains(_selectedLevel)) {
        return false;
      }
      if (_selectedSkill != null && !m.skills.contains(_selectedSkill)) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context, l10n),
              _buildFilterChips(context, l10n),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: homeMaxWidth(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, method) in filteredMethods.indexed)
                              SlideIn(
                                delay: Duration(milliseconds: 60 + 60 * i),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _MethodCard(
                                    repo: repo,
                                    progress: progress,
                                    method: method,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => MethodPage(
                                            repo: repo,
                                            progress: progress,
                                            method: method,
                                            onPlay: widget.onPlay,
                                          ),
                                        ),
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.methodsLibraryTitle.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Audiowide',
              fontSize: 20,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFD54F),
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.progress.totalMethodStars}',
                style: const TextStyle(
                  fontFamily: 'Audiowide',
                  fontSize: 15,
                  color: Color(0xFFFFD54F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, AppLocalizations l10n) {
    final levelLabels = <String, String>{
      'beginner': l10n.methodsFilterBeginner,
      'early-intermediate': l10n.methodsFilterEarlyIntermediate,
      'intermediate': l10n.methodsFilterIntermediate,
    };

    final skillLabels = <String, String>{
      'reading': l10n.methodsFilterReading,
      'rhythm': l10n.methodsFilterRhythm,
      'independence': l10n.methodsFilterIndependence,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: l10n.methodsFilterAll,
            selected: _selectedLevel == null && _selectedSkill == null,
            onTap: () => setState(() {
              _selectedLevel = null;
              _selectedSkill = null;
            }),
          ),
          const SizedBox(width: 8),
          for (final entry in levelLabels.entries) ...[
            _FilterChip(
              label: entry.value,
              selected: _selectedLevel == entry.key,
              onTap: () => setState(() {
                _selectedLevel = _selectedLevel == entry.key ? null : entry.key;
              }),
            ),
            const SizedBox(width: 8),
          ],
          for (final entry in skillLabels.entries) ...[
            _FilterChip(
              label: entry.value,
              selected: _selectedSkill == entry.key,
              onTap: () => setState(() {
                _selectedSkill = _selectedSkill == entry.key ? null : entry.key;
              }),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          shape: chamfer(
            12,
            side: BorderSide(
              color: selected
                  ? GameColors.cyan
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
          ),
          gradient: LinearGradient(
            colors: selected
                ? [
                    GameColors.cyan.withValues(alpha: 0.35),
                    const Color(0xFF1E1442),
                  ]
                : [const Color(0xFF221A52), const Color(0xFF16103A)],
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : GameColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.repo,
    required this.progress,
    required this.method,
    required this.onTap,
  });

  final ContentRepo repo;
  final Progress progress;
  final MethodDef method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stars = progress.methodStars(method);
    final maxStars = progress.methodMaxStars(method);
    final ratio = maxStars > 0 ? (stars / maxStars).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: ShapeDecoration(
          shape: chamfer(
            18,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C1F68), Color(0xFF1C1348), Color(0xFF140D34)],
          ),
          shadows: [
            BoxShadow(
              color: const Color(0xFF6B21A8).withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: chamfer(18)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (method.composer.isNotEmpty) ...[
                  Text(
                    method.composer.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 12,
                      color: GameColors.cyan,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        repo.t(method.title),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 26,
                    ),
                  ],
                ),
                if (method.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    repo.t(method.description),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Badge(
                      label: l10n.methodsBookCount(method.books.length),
                      color: const Color(0xFF8B5CF6),
                    ),
                    for (final skill in method.skills)
                      _Badge(
                        label: _skillLabel(skill, l10n),
                        color: const Color(0xFF06B6D4),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: GameProgressBar(value: ratio, height: 8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD54F),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$stars / $maxStars',
                          style: const TextStyle(
                            fontFamily: 'Audiowide',
                            fontSize: 13,
                            color: Color(0xFFFFD54F),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _skillLabel(String key, AppLocalizations l10n) {
    switch (key) {
      case 'reading':
        return l10n.methodsFilterReading;
      case 'rhythm':
        return l10n.methodsFilterRhythm;
      case 'independence':
        return l10n.methodsFilterIndependence;
      default:
        return key;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        color: color.withValues(alpha: 0.18),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}
