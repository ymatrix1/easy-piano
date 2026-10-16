import 'package:flutter/material.dart';

import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'home_page.dart' show Progress;

/// Practice tab: training modes outside the course path.
class PracticeTab extends StatelessWidget {
  const PracticeTab({super.key, required this.onFreePlay});

  final VoidCallback onFreePlay;

  @override
  Widget build(BuildContext context) {
    final modes = [
      (
        'Free play',
        'Play anything on your MIDI keyboard or the screen.',
        Icons.piano_rounded,
        GameTone.blue,
        onFreePlay as VoidCallback?,
      ),
      (
        'Sight reading',
        'Read short random phrases at your level.',
        Icons.visibility_rounded,
        GameTone.purple,
        null,
      ),
      (
        'Rhythm drills',
        'Tap the beat: quarters, halves, eighths.',
        Icons.av_timer_rounded,
        GameTone.green,
        null,
      ),
      (
        'Song library',
        'Practice any song you unlocked, at any tempo.',
        Icons.library_music_rounded,
        GameTone.red,
        null,
      ),
    ];
    return _TabScroll(
      title: 'Practice',
      subtitle: 'Train skills outside the course path.',
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 2 : 1;
          final w = (c.maxWidth - 14 * (cols - 1)) / cols;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final (i, (title, desc, icon, tone, onTap)) in modes.indexed)
                SizedBox(
                  width: w,
                  child: SlideIn(
                    delay: Duration(milliseconds: 60 * i),
                    child: _ModeCard(
                      title: title,
                      description: desc,
                      icon: icon,
                      tone: tone,
                      onTap: onTap,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final GameTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null;
    final t = locked ? GameTone.grey : tone;
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      builder: (p, hover) => Transform.scale(
        scale: 1 - 0.02 * p,
        child: Container(
          height: 150,
          decoration: ShapeDecoration(
            shape: chamfer(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                hover ? Color.lerp(t.top, Colors.white, 0.08)! : t.top,
                t.bottom,
              ],
            ),
            shadows: [
              BoxShadow(
                color: (hover ? t.top : Colors.black).withValues(alpha: 0.35),
                blurRadius: hover ? 22 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: chamfer(16)),
            child: Stack(
              children: [
                Positioned(
                  right: -16,
                  bottom: -22,
                  child: Icon(
                    icon,
                    size: 120,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Colors.white, size: 28),
                      const Spacer(),
                      GameText(
                        title,
                        size: 22,
                        align: TextAlign.left,
                        color: locked ? t.label : Colors.white,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: locked ? 0.45 : 0.85,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked)
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: ShapeDecoration(
                        shape: chamfer(6),
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: const Text(
                        'SOON',
                        style: TextStyle(
                          color: GameColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile tab: totals and developer tools.
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.progress,
    required this.onMidiSpike,
    required this.onStaffSpike,
  });

  final Progress progress;
  final VoidCallback onMidiSpike;
  final VoidCallback onStaffSpike;

  @override
  Widget build(BuildContext context) {
    final modules = progress.repo.courses
        .where(
          (c) =>
              !c.planned &&
              c.nodes.isNotEmpty &&
              c.nodes.every((n) => progress.nodeStars(n) > 0),
        )
        .length;
    final stats = [
      ('Stars', progress.totalStars, Icons.star_rounded, GameColors.gold),
      (
        'Tasks',
        progress.tasksDone,
        Icons.check_circle_rounded,
        GameColors.success,
      ),
      ('Modules', modules, Icons.workspace_premium_rounded, GameColors.cyan),
    ];
    return _TabScroll(
      title: 'Profile',
      subtitle: 'Your progress on this device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, (label, value, icon, color)) in stats.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: PopIn(
                    delay: Duration(milliseconds: 80 * i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: ShapeDecoration(
                        shape: chamfer(
                          14,
                          side: const BorderSide(color: GameColors.panelEdge),
                        ),
                        color: GameColors.panel.withValues(alpha: 0.9),
                      ),
                      child: Column(
                        children: [
                          Icon(icon, color: color, size: 28),
                          const SizedBox(height: 8),
                          CountUp(value: value.toDouble(), size: 28),
                          const SizedBox(height: 2),
                          Text(
                            label.toUpperCase(),
                            style: const TextStyle(
                              color: GameColors.textDim,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          const GameText('Developer tools', size: 16, align: TextAlign.left),
          const SizedBox(height: 10),
          _ListButton('MIDI latency spike', Icons.usb_rounded, onMidiSpike),
          const SizedBox(height: 8),
          _ListButton(
            'Staff render spike',
            Icons.queue_music_rounded,
            onStaffSpike,
          ),
        ],
      ),
    );
  }
}

class _ListButton extends StatelessWidget {
  const _ListButton(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (p, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          shape: chamfer(
            10,
            side: const BorderSide(color: GameColors.panelEdge),
          ),
          color: GameColors.panel.withValues(alpha: hover ? 1 : 0.85),
        ),
        child: Row(
          children: [
            Icon(icon, color: GameColors.cyan, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: GameColors.textDim),
          ],
        ),
      ),
    );
  }
}

/// Scrollable tab body with a big title.
class _TabScroll extends StatelessWidget {
  const _TabScroll({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameText(title, size: 34, align: TextAlign.left),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: GameColors.textDim,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
