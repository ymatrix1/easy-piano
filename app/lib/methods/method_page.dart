import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../home/home_page.dart';
import '../home/task_sheet.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';

/// Screen for a specific method (e.g. Mikrokosmos) with description and collapsible books.
class MethodPage extends StatefulWidget {
  const MethodPage({
    super.key,
    required this.repo,
    required this.progress,
    required this.method,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final MethodDef method;
  final Future<void> Function(String levelId, [int initialStageIndex]) onPlay;

  @override
  State<MethodPage> createState() => _MethodPageState();
}

class _MethodPageState extends State<MethodPage> {
  final Set<String> _openBooks = {};

  @override
  void initState() {
    super.initState();
    _initOpenBooks();
  }

  void _initOpenBooks() {
    // Open the first unfinished book, or the first book if all are finished.
    for (final bookId in widget.method.books) {
      final c = widget.repo.courses.where((c) => c.id == bookId).firstOrNull;
      if (c == null) continue;
      final max = c.nodes.length * 3;
      if (max == 0 || widget.progress.courseStars(c) < max) {
        _openBooks.add(bookId);
        break;
      }
    }
    if (_openBooks.isEmpty && widget.method.books.isNotEmpty) {
      _openBooks.add(widget.method.books.first);
    }
  }

  Future<void> _openPiece(CourseDef course, JourneyNode node) async {
    final selection = await showModalBottomSheet<(String, int)>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TaskSheet(
        repo: widget.repo,
        progress: widget.progress,
        course: course,
        node: node,
      ),
    );
    if (selection != null) {
      await widget.onPlay(selection.$1, selection.$2);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = widget.repo;
    final progress = widget.progress;
    final method = widget.method;

    final nextPiece = progress.nextInMethod(method);

    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context, repo, method),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: homeMaxWidth(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroCard(
                              context,
                              l10n,
                              repo,
                              progress,
                              method,
                              nextPiece,
                            ),
                            const SizedBox(height: 20),
                            for (final (i, bookId) in method.books.indexed) ...[
                              _buildBookSection(
                                context,
                                l10n,
                                repo,
                                progress,
                                bookId,
                                i,
                              ),
                              const SizedBox(height: 14),
                            ],
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

  Widget _buildTopBar(
    BuildContext context,
    ContentRepo repo,
    MethodDef method,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            mouseCursor: SystemMouseCursors.click,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (method.composer.isNotEmpty)
                  Text(
                    method.composer.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 11,
                      color: GameColors.cyan,
                      letterSpacing: 1.1,
                    ),
                  ),
                Text(
                  repo.t(method.title),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
                '${widget.progress.methodStars(method)}',
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

  Widget _buildHeroCard(
    BuildContext context,
    AppLocalizations l10n,
    ContentRepo repo,
    Progress progress,
    MethodDef method,
    (CourseDef, JourneyNode)? nextPiece,
  ) {
    final stars = progress.methodStars(method);
    final maxStars = progress.methodMaxStars(method);

    return Container(
      decoration: ShapeDecoration(
        shape: chamfer(
          20,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1C6A), Color(0xFF1E134C), Color(0xFF130B34)],
        ),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: chamfer(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (method.description.isNotEmpty) ...[
                Text(
                  repo.t(method.description),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFD54F),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$stars / $maxStars',
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 14,
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.methodsBookCount(method.books.length),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (nextPiece != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'NEXT: ',
                      style: TextStyle(
                        fontFamily: 'Audiowide',
                        fontSize: 12,
                        color: GameColors.cyan,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        repo.t(nextPiece.$2.title),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GameButton(
                  label: l10n.methodContinue,
                  icon: Icons.play_arrow_rounded,
                  tone: GameTone.gold,
                  fontSize: 16,
                  height: 48,
                  onTap: () => _openPiece(nextPiece.$1, nextPiece.$2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookSection(
    BuildContext context,
    AppLocalizations l10n,
    ContentRepo repo,
    Progress progress,
    String bookId,
    int index,
  ) {
    final course = repo.courses.where((c) => c.id == bookId).firstOrNull;
    if (course == null) return const SizedBox.shrink();

    final isOpen = _openBooks.contains(bookId);
    final bookStars = progress.courseStars(course);
    final maxBookStars = course.nodes.length * 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: ShapeDecoration(
          shape: chamfer(
            16,
            side: BorderSide(
              color: isOpen
                  ? GameColors.cyan.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.12),
              width: isOpen ? 1.3 : 1,
            ),
          ),
          color: const Color(0xFF1B144A).withValues(alpha: 0.85),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: chamfer(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    Sfx.play(SfxKind.open);
                    setState(() {
                      if (isOpen) {
                        _openBooks.remove(bookId);
                      } else {
                        _openBooks.add(bookId);
                      }
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                repo.t(course.title),
                                style: const TextStyle(
                                  fontFamily: 'Audiowide',
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.taskCount(course.nodes.length),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFD54F),
                              size: 17,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$bookStars / $maxBookStars',
                              style: const TextStyle(
                                fontFamily: 'Audiowide',
                                fontSize: 12,
                                color: Color(0xFFFFD54F),
                              ),
                            ),
                            const SizedBox(width: 10),
                            AnimatedRotation(
                              turns: isOpen ? 0.25 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isOpen) ...[
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      for (final node in course.nodes)
                        _PieceTile(
                          repo: repo,
                          progress: progress,
                          course: course,
                          node: node,
                          onTap: () => _openPiece(course, node),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PieceTile extends StatefulWidget {
  const _PieceTile({
    required this.repo,
    required this.progress,
    required this.course,
    required this.node,
    required this.onTap,
  });

  final ContentRepo repo;
  final Progress progress;
  final CourseDef course;
  final JourneyNode node;
  final VoidCallback onTap;

  @override
  State<_PieceTile> createState() => _PieceTileState();
}

class _PieceTileState extends State<_PieceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final stars = widget.progress.nodeStars(widget.node);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: _hover
                      ? GameColors.cyan.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              color: _hover
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.repo.t(widget.node.title),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                StarRow(stars: stars.toDouble(), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
