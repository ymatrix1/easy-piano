import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../practice/level_page.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/staff/staff_spike_page.dart';

/// Course map: each course is a winding trail of level nodes over a sky
/// backdrop (see docs/specs/visual-style.md and docs/specs/course-map.md).
/// Progress lives in memory until the progress store lands (Phase 2).
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repo,
    required this.midi,
    required this.spikes,
  });

  final ContentRepo repo;
  final MidiInput midi;

  /// Opens the Phase 0 MIDI spike page.
  final WidgetBuilder spikes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _stars = <String, int>{}; // node id → stars

  Future<void> _open(JourneyNode node) async {
    final level = widget.repo.levels[node.levels.first];
    if (level == null) return;
    final stars = await Navigator.of(context).push<int>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) =>
            LevelPage(repo: widget.repo, level: level, midi: widget.midi),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(
              begin: 1.08,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
    if (stars != null && stars > (_stars[node.id] ?? 0)) {
      setState(() => _stars[node.id] = stars);
    }
  }

  void _openSpike(String v) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: v == 'midi' ? widget.spikes : (_) => const StaffSpikePage(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final total = _stars.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                child: Row(
                  children: [
                    const PopIn(child: _LogoPlaque()),
                    const Spacer(),
                    PopIn(
                      delay: const Duration(milliseconds: 150),
                      child: StarCounter(value: total),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      tooltip: 'Developer spikes',
                      onSelected: _openSpike,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'midi', child: Text('MIDI spike')),
                        PopupMenuItem(
                          value: 'staff',
                          child: Text('Staff spike'),
                        ),
                      ],
                      child: const IgnorePointer(
                        child: GameRoundButton(
                          icon: Icons.settings_rounded,
                          onTap: _noop,
                          tone: GameTone.wood,
                          size: 46,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    for (final course in repo.courses)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _CourseTrail(
                            title: repo.t(course.title),
                            description: repo.t(course.description),
                            nodes: course.nodes,
                            label: (n) => repo.t(n.title),
                            stars: _stars,
                            onOpen: _open,
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
}

void _noop() {}

class _LogoPlaque extends StatelessWidget {
  const _LogoPlaque();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 18, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GameColors.outline, width: 3),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GameColors.wood, GameColors.woodDark],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 5)),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.piano_rounded, color: GameColors.goldLight, size: 30),
          SizedBox(width: 8),
          GameText('Easy Piano', size: 26, color: GameColors.goldLight),
        ],
      ),
    );
  }
}

/// One course: ribbon header, then nodes zig-zagging down a dotted trail.
class _CourseTrail extends StatelessWidget {
  const _CourseTrail({
    required this.title,
    required this.description,
    required this.nodes,
    required this.label,
    required this.stars,
    required this.onOpen,
  });

  final String title;
  final String description;
  final List<JourneyNode> nodes;
  final String Function(JourneyNode) label;
  final Map<String, int> stars;
  final void Function(JourneyNode) onOpen;

  static const _rowH = 132.0;
  static const _nodeSize = 84.0;

  /// Horizontal position of node [i] as a fraction of the width.
  static double _x(int i) => 0.5 + 0.28 * math.sin(i * 1.15);

  GameTone _tone(String kind) => switch (kind) {
    'song' => GameTone.green,
    'boss' || 'mini_boss' => GameTone.red,
    'star_gate' => GameTone.gold,
    _ => GameTone.blue,
  };

  IconData _icon(String kind) => switch (kind) {
    'song' => Icons.music_note_rounded,
    'boss' || 'mini_boss' => Icons.emoji_events_rounded,
    'star_gate' => Icons.star_rounded,
    _ => Icons.school_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final next = nodes.indexWhere((n) => (stars[n.id] ?? 0) == 0);
    return Column(
      children: [
        const SizedBox(height: 12),
        SlideIn(
          offset: const Offset(0, -30),
          child: GameRibbon(title, tone: GameTone.red, fontSize: 28),
        ),
        const SizedBox(height: 8),
        SlideIn(
          delay: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: GameColors.parchment.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GameColors.outline, width: 2.5),
            ),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: GameColors.outline,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: nodes.length * _rowH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrailPainter(
                        points: [
                          for (var i = 0; i < nodes.length; i++)
                            Offset(_x(i) * w, i * _rowH + _nodeSize / 2 + 8),
                        ],
                      ),
                    ),
                  ),
                  for (final (i, node) in nodes.indexed)
                    Positioned(
                      left: _x(i) * w - 80,
                      top: i * _rowH,
                      width: 160,
                      child: PopIn(
                        delay: Duration(milliseconds: 200 + 70 * i),
                        child: _NodeButton(
                          title: label(node),
                          index: i + 1,
                          tone: _tone(node.kind),
                          icon: _icon(node.kind),
                          stars: stars[node.id] ?? 0,
                          isNext: i == next,
                          size: _nodeSize,
                          onTap: () => onOpen(node),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NodeButton extends StatelessWidget {
  const _NodeButton({
    required this.title,
    required this.index,
    required this.tone,
    required this.icon,
    required this.stars,
    required this.isNext,
    required this.size,
    required this.onTap,
  });

  final String title;
  final int index;
  final GameTone tone;
  final IconData icon;
  final int stars;
  final bool isNext;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget node = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        GameRoundButton(
          icon: icon,
          onTap: onTap,
          tone: tone,
          size: size,
          tooltip: '$index. $title',
        ),
        if (isNext)
          const Positioned(top: -22, child: IgnorePointer(child: _PlayTag())),
      ],
    );
    if (isNext) node = Bob(child: node);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        node,
        Transform.translate(
          offset: const Offset(0, -10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var s = 0; s < 3; s++)
                GameStar(fill: s < stars ? 1 : 0, size: 20),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -10),
          child: GameText(title, size: 15, stroke: 2),
        ),
      ],
    );
  }
}

class _PlayTag extends StatelessWidget {
  const _PlayTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: GameColors.gold,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameColors.outline, width: 2.5),
      ),
      child: const GameText('PLAY', size: 14, stroke: 2),
    );
  }
}

/// Dotted path joining the nodes.
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.points});

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final mid = (a.dy + b.dy) / 2;
      path.cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
    }
    // Wide sandy road with an outline, then dashes down its middle.
    canvas.drawPath(
      path,
      Paint()
        ..color = GameColors.outline.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF2D59A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round,
    );
    final dash = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 22) {
        final t = m.getTangentForOffset(d);
        if (t != null) canvas.drawCircle(t.position, 3.2, dash);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.points != points;
}
