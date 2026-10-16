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

  void _onMenu(String v) {
    if (v.startsWith('skin:')) {
      skinNotifier.value = GameSkin.all.firstWhere((s) => 'skin:${s.id}' == v);
      return;
    }
    _openSpike(v);
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
      body: MenuBackground(
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
                      tooltip: 'Settings',
                      onSelected: _onMenu,
                      itemBuilder: (_) => [
                        for (final s in GameSkin.all)
                          CheckedPopupMenuItem(
                            value: 'skin:${s.id}',
                            checked: s == skinNotifier.value,
                            child: Text('Theme: ${s.label}'),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'midi',
                          child: Text('MIDI spike'),
                        ),
                        const PopupMenuItem(
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
    final skin = GameSkin.of(context);
    final wood = skin.tone(GameTone.wood);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 18, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(skin.radius),
        border: Border.all(
          color: skin.playful ? skin.outline : skin.panelFrame,
          width: skin.playful ? 3 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wood.face, wood.lip],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 5)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.piano_rounded, color: skin.accentLight, size: 28),
          const SizedBox(width: 8),
          GameText('Easy Piano', size: 24, color: skin.accentLight),
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

  /// Splits the journey into parts: a part ends after a song, boss or star
  /// gate. Interim grouping until journeys declare sections in content.
  static List<List<(int, JourneyNode)>> _parts(List<JourneyNode> nodes) {
    final parts = <List<(int, JourneyNode)>>[[]];
    for (final (i, n) in nodes.indexed) {
      parts.last.add((i, n));
      final ends = const {'song', 'boss', 'mini_boss', 'star_gate'};
      if (ends.contains(n.kind) && i < nodes.length - 1) parts.add([]);
    }
    return parts.where((p) => p.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final next = nodes.indexWhere((n) => (stars[n.id] ?? 0) == 0);
    final skin = GameSkin.of(context);
    final parts = _parts(nodes);
    return Column(
      children: [
        const SizedBox(height: 12),
        SlideIn(
          offset: const Offset(0, -30),
          child: GameRibbon(title, tone: GameTone.red, fontSize: 28),
        ),
        const SizedBox(height: 10),
        SlideIn(
          delay: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: skin.playful
                ? BoxDecoration(
                    color: const Color(0x33103A66),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: skin.playful ? Colors.white : skin.panelText,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.35,
                shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        for (final (p, part) in parts.indexed) ...[
          SlideIn(
            delay: Duration(milliseconds: 180 + 120 * p),
            child: _PartCard(
              number: p + 1,
              earned: part.fold(0, (a, e) => a + (stars[e.$2.id] ?? 0)),
              total: part.length * 3,
              levels: part.length,
              child: _PartTrail(
                part: part,
                next: next,
                label: label,
                stars: stars,
                onOpen: onOpen,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

/// A group of levels: header (part number, level count, stars) over a card
/// holding that part's trail.
class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.number,
    required this.earned,
    required this.total,
    required this.levels,
    required this.child,
  });

  final int number;
  final int earned;
  final int total;
  final int levels;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    final headerStyle = TextStyle(
      color: skin.playful ? Colors.white : skin.accentLight,
      fontWeight: FontWeight.w800,
      fontSize: 13,
      letterSpacing: 1.4,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(skin.playful ? 22 : 16),
        color: skin.playful
            ? Colors.white.withValues(alpha: 0.18)
            : skin.panelFill.withValues(alpha: 0.55),
        border: Border.all(
          color: skin.playful
              ? Colors.white.withValues(alpha: 0.55)
              : skin.panelFrame,
          width: skin.playful ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: skin.playful
                      ? Colors.white.withValues(alpha: 0.4)
                      : skin.panelFrame,
                ),
              ),
            ),
            child: Row(
              children: [
                Text('PART $number', style: headerStyle),
                const SizedBox(width: 10),
                Text(
                  '$levels ${levels == 1 ? 'level' : 'levels'}',
                  style: headerStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: headerStyle.color!.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                GameStar(fill: 1, size: 18),
                const SizedBox(width: 6),
                Text('$earned / $total', style: headerStyle),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Zig-zag trail of one part's nodes.
class _PartTrail extends StatelessWidget {
  const _PartTrail({
    required this.part,
    required this.next,
    required this.label,
    required this.stars,
    required this.onOpen,
  });

  final List<(int, JourneyNode)> part;
  final int next;
  final String Function(JourneyNode) label;
  final Map<String, int> stars;
  final void Function(JourneyNode) onOpen;

  static const _nodeSize = 76.0;
  static const _tagH = 26.0; // room for the PLAY / NEXT tag
  static const _rowH = 168.0;
  static const _cellW = 136.0;

  /// Horizontal position of node [i] as a fraction of the width.
  /// Alternates centre, right, centre, left so consecutive nodes are always
  /// a fixed step apart and the trail can pass beside each label.
  static double _x(int i) => const [0.5, 0.72, 0.5, 0.28][i % 4];

  /// Trail from the side of node [k] (at its centre height) to the top of
  /// the next node, so it never crosses stars or titles.
  static (Offset, Offset) _link(double x0, double x1, int k) {
    final cy = k * _rowH + _tagH + _nodeSize / 2;
    final dir = (x1 - x0).sign;
    return (
      Offset(x0 + dir * _nodeSize / 2, cy),
      Offset(x1, (k + 1) * _rowH + _tagH - 2),
    );
  }

  static GameTone _tone(String kind) => switch (kind) {
    'song' => GameTone.green,
    'boss' || 'mini_boss' => GameTone.red,
    'star_gate' => GameTone.gold,
    _ => GameTone.blue,
  };

  static IconData _icon(String kind) => switch (kind) {
    'song' => Icons.music_note_rounded,
    'boss' || 'mini_boss' => Icons.emoji_events_rounded,
    'star_gate' => Icons.star_rounded,
    _ => Icons.school_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double cx(int i) =>
            (_x(i) * w).clamp(_cellW / 2, math.max(_cellW / 2, w - _cellW / 2));
        return SizedBox(
          height: part.length * _rowH,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TrailPainter(
                    skin: skin,
                    links: [
                      for (var k = 0; k + 1 < part.length; k++)
                        _link(cx(part[k].$1), cx(part[k + 1].$1), k),
                    ],
                  ),
                ),
              ),
              for (final (k, (i, node)) in part.indexed)
                Positioned(
                  left: cx(i) - _cellW / 2,
                  top: k * _rowH,
                  width: _cellW,
                  height: _rowH,
                  child: PopIn(
                    delay: Duration(milliseconds: 250 + 70 * i),
                    child: _NodeButton(
                      title: label(node),
                      index: i + 1,
                      tone: _tone(node.kind),
                      icon: _icon(node.kind),
                      stars: stars[node.id] ?? 0,
                      isNext: i == next,
                      size: _nodeSize,
                      tagHeight: _tagH,
                      onTap: () => onOpen(node),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One level node: tag slot, round button, stars, then the title. Each piece
/// has its own row so nothing overlaps.
class _NodeButton extends StatelessWidget {
  const _NodeButton({
    required this.title,
    required this.index,
    required this.tone,
    required this.icon,
    required this.stars,
    required this.isNext,
    required this.size,
    required this.tagHeight,
    required this.onTap,
  });

  final String title;
  final int index;
  final GameTone tone;
  final IconData icon;
  final int stars;
  final bool isNext;
  final double size;
  final double tagHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    Widget button = GameRoundButton(
      icon: icon,
      onTap: onTap,
      tone: tone,
      size: size,
      tooltip: '$index. $title',
    );
    if (isNext) button = Bob(amplitude: 4, child: button);
    return Column(
      children: [
        SizedBox(
          height: tagHeight,
          child: isNext
              ? const Align(alignment: Alignment.topCenter, child: _PlayTag())
              : null,
        ),
        button,
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var s = 0; s < 3; s++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: GameStar(fill: s < stars ? 1 : 0, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: skin.playful ? FontWeight.w800 : FontWeight.w600,
            height: 1.2,
            shadows: [
              Shadow(
                color: skin.playful ? Colors.black54 : Colors.black45,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayTag extends StatelessWidget {
  const _PlayTag();

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: skin.playful ? skin.accent : skin.bgTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: skin.playful ? skin.outline : skin.accent,
          width: skin.playful ? 2.5 : 1,
        ),
      ),
      child: GameText(
        skin.playful ? 'PLAY' : 'NEXT',
        size: skin.playful ? 14 : 11,
        stroke: 2,
        color: skin.playful ? Colors.white : skin.accentLight,
      ),
    );
  }
}

/// Path joining the nodes: a sandy dotted road (playful) or a thin dashed
/// brass line (classic).
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.skin, required this.links});

  final GameSkin skin;
  final List<(Offset, Offset)> links;

  @override
  void paint(Canvas canvas, Size size) {
    if (links.isEmpty) return;
    final path = Path();
    for (final (a, b) in links) {
      // Leave sideways, then turn down into the next node.
      path
        ..moveTo(a.dx, a.dy)
        ..cubicTo(b.dx, a.dy, b.dx, a.dy, b.dx, b.dy);
    }
    if (!skin.playful) {
      final dash = Paint()
        ..color = skin.trail
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 14) {
          canvas.drawPath(m.extractPath(d, d + 7), dash);
        }
      }
      return;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = skin.outline.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = skin.trail
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 22) {
        final t = m.getTangentForOffset(d);
        if (t != null) canvas.drawCircle(t.position, 3.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.links != links || old.skin != skin;
}
