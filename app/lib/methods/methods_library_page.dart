import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../home/home_page.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import 'method_page.dart';

/// Methods library screen: browsable catalog of piano methods outside the main course.
class MethodsLibraryPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
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
                          '${progress.totalMethodStars}',
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
              ),
              Expanded(
                child: MethodsCatalogView(
                  repo: repo,
                  progress: progress,
                  onPlay: onPlay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog view of methods with filter chips and method cards.
/// Can be embedded inline in the Learn tab or shown in [MethodsLibraryPage].
class MethodsCatalogView extends StatefulWidget {
  const MethodsCatalogView({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId) onPlay;

  @override
  State<MethodsCatalogView> createState() => _MethodsCatalogViewState();
}

class _MethodsCatalogViewState extends State<MethodsCatalogView> {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: homeMaxWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilterChips(context, l10n),
                const SizedBox(height: 18),
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
                if (filteredMethods.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        l10n.methodsFilterAll,
                        style: const TextStyle(
                          color: GameColors.textDim,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF140D36).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: l10n.methodsFilterAll,
                selected: _selectedLevel == null && _selectedSkill == null,
                onTap: () {
                  Sfx.play(SfxKind.tab);
                  setState(() {
                    _selectedLevel = null;
                    _selectedSkill = null;
                  });
                },
              ),
              for (final entry in levelLabels.entries)
                _FilterChip(
                  label: entry.value,
                  selected: _selectedLevel == entry.key,
                  onTap: () {
                    Sfx.play(SfxKind.tab);
                    setState(() {
                      _selectedLevel = _selectedLevel == entry.key
                          ? null
                          : entry.key;
                    });
                  },
                ),
              for (final entry in skillLabels.entries)
                _FilterChip(
                  label: entry.value,
                  selected: _selectedSkill == entry.key,
                  onTap: () {
                    Sfx.play(SfxKind.tab);
                    setState(() {
                      _selectedSkill = _selectedSkill == entry.key
                          ? null
                          : entry.key;
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? GameColors.cyan
                  : _hover
                  ? Colors.white38
                  : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? GameColors.cyan.withValues(alpha: 0.22)
                : _hover
                ? const Color(0xFF261D5A)
                : const Color(0xFF1B1446),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: GameColors.cyan.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : (_hover ? Colors.white70 : GameColors.textDim),
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatefulWidget {
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
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = widget.repo;
    final progress = widget.progress;
    final method = widget.method;

    final stars = progress.methodStars(method);
    final maxStars = progress.methodMaxStars(method);
    final ratio = maxStars > 0 ? (stars / maxStars).clamp(0.0, 1.0) : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: ShapeDecoration(
            shape: chamfer(
              16,
              side: BorderSide(
                color: _hover
                    ? GameColors.cyan.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.14),
                width: 1.2,
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _hover ? const Color(0xFF342378) : const Color(0xFF281C60),
                const Color(0xFF1B1245),
                const Color(0xFF120C30),
              ],
            ),
            shadows: [
              BoxShadow(
                color: _hover
                    ? const Color(0xFF6B21A8).withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.35),
                blurRadius: _hover ? 24 : 14,
                offset: Offset(0, _hover ? 6 : 3),
              ),
            ],
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: chamfer(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
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
                            Text(
                              repo.t(method.title),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 14,
                              color: GameColors.cyan,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              l10n
                                  .methodsBookCount(method.books.length)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'Audiowide',
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (method.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      repo.t(method.description),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  if (method.skills.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in method.skills)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              _skillLabel(s, l10n),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 160,
                              child: GameProgressBar(value: ratio),
                            ),
                          ],
                        ),
                      ),
                      GameButton(
                        label: l10n.methodsExplore,
                        icon: Icons.arrow_forward_rounded,
                        tone: GameTone.gold,
                        fontSize: 14,
                        minWidth: 120,
                        height: 42,
                        onTap: widget.onTap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _skillLabel(String s, AppLocalizations l10n) => switch (s) {
    'reading' => l10n.methodsFilterReading,
    'rhythm' => l10n.methodsFilterRhythm,
    'independence' => l10n.methodsFilterIndependence,
    _ => s,
  };
}
