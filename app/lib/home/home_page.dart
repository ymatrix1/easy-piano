import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../practice/free_play_page.dart';
import '../practice/generated/practice_service.dart';
import '../practice/generated/stream_practice_page.dart';
import '../practice/generated/tune_generator.dart';
import '../practice/level_page.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import '../ui/staff/staff_spike_page.dart';
import '../ui/window/window_title_bar.dart';
import 'learn_tab.dart';
import 'other_tabs.dart';

/// Main menu: top bar, one of the tabs (Learn, Practice, Profile) and the
/// bottom navigation bar. See docs/specs/visual-style.md.
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

  /// Opens the Phase 0 MIDI latency spike page (developer tools).
  final WidgetBuilder spikes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _stars = <String, int>{}; // level id → best stars
  int _tab = 0;

  Future<void> _playLevel(String levelId, [int initialStageIndex = 0]) async {
    final level = widget.repo.levels[levelId];
    if (level == null) return;
    final stars = await Navigator.of(context).push<int>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => LevelPage(
          repo: widget.repo,
          level: level,
          midi: widget.midi,
          initialStageIndex: initialStageIndex,
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(
              begin: 1.06,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
    if (stars != null && stars > (_stars[levelId] ?? 0)) {
      setState(() => _stars[levelId] = stars);
    }
  }

  /// One generator per app session, so the model loads once (D28).
  late final TuneGenerator? _generator = widget.repo.melodyManifest == null
      ? null
      : createTuneGenerator(widget.repo.melodyManifest!);

  void _push(WidgetBuilder b) =>
      Navigator.of(context).push(MaterialPageRoute(builder: b));

  @override
  Widget build(BuildContext context) {
    final progress = Progress(widget.repo, _stars);
    final tabs = [
      LearnTab(repo: widget.repo, progress: progress, onPlay: _playLevel),
      SafeArea(
        bottom: false,
        child: PracticeTab(
          onFreePlay: () => _push((_) => FreePlayPage(midi: widget.midi)),
          onEndless: _generator == null || widget.repo.practice.isEmpty
              ? null
              : () => _push(
                  (_) => StreamSetupPage(
                    repo: widget.repo,
                    generator: _generator,
                    midi: widget.midi,
                    initialNode: switch (progress.next) {
                      (final c, final n) => '${c.id}/${n.id}',
                      null => null,
                    },
                  ),
                ),
        ),
      ),
      ProfileTab(
        progress: progress,
        onMidiSpike: () => _push(widget.spikes),
        onStaffSpike: () => _push((_) => const StaffSpikePage()),
      ),
    ];
    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Tabs scroll under the floating glass bar: their top inset
                    // comes in as MediaQuery padding.
                    Positioned.fill(
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          padding: MediaQuery.paddingOf(context)
                              .copyWith(top: _TopBar.inset),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.02),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(_tab),
                            child: tabs[_tab],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _TopBar(stars: progress.totalStars),
                    ),
                    if (usesCustomTitleBar)
                      const Positioned(
                        top: 0,
                        right: 0,
                        child: WindowControls(),
                      ),
                  ],
                ),
              ),
              _NavBar(index: _tab, onSelect: (i) => setState(() => _tab = i)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stars per level, rolled up to submodules (journey nodes) and modules.
class Progress {
  Progress(this.repo, this.levelStars);

  final ContentRepo repo;
  final Map<String, int> levelStars;

  /// A submodule's stars: the lowest of its tasks (0 until all are played).
  /// A star gate scores its earned stars against `starsNeeded` instead, so
  /// any mix of its songs can open it.
  int nodeStars(JourneyNode n) {
    if (n.levels.isEmpty) return 0;
    final need = n.starsNeeded;
    if (need != null) return (3 * gateStars(n) ~/ need).clamp(0, 3);
    return n.levels
        .map((l) => levelStars[l] ?? 0)
        .reduce((a, b) => a < b ? a : b);
  }

  /// Passed: a gate has its stars, any other node has every task played.
  bool nodeDone(JourneyNode n) =>
      n.starsNeeded != null ? gateStars(n) >= n.starsNeeded! : nodeStars(n) > 0;

  /// Stars earned so far across a node's tasks.
  int gateStars(JourneyNode n) =>
      n.levels.fold(0, (a, l) => a + (levelStars[l] ?? 0));

  int courseStars(CourseDef c) => c.nodes.fold(0, (a, n) => a + nodeStars(n));

  int get totalStars => levelStars.values.fold(0, (a, b) => a + b);

  int get tasksDone => levelStars.values.where((s) => s > 0).length;

  /// First unfinished submodule in the first unfinished module.
  (CourseDef, JourneyNode)? get next {
    for (final c in repo.courses) {
      if (c.planned) continue;
      for (final n in c.nodes) {
        if (!nodeDone(n)) return (c, n);
      }
    }
    return null;
  }

  /// First task of [n] not yet played (or its first task).
  String firstOpenLevel(JourneyNode n) => n.levels.firstWhere(
    (l) => (levelStars[l] ?? 0) == 0,
    orElse: () => n.levels.first,
  );
}

/// On Windows the caption buttons take the top-right corner; below this width
/// the star counter would sit under them, so it is hidden.
const _starHideWidth = 1200.0;

class _TopBar extends StatelessWidget {
  const _TopBar({required this.stars});

  final int stars;

  static const _height = 60.0;

  /// Space the tabs leave at the top so their first item starts below the bar.
  static const inset = _height + 8;

  @override
  Widget build(BuildContext context) {
    // Edge-to-edge glass bar, mirroring the bottom nav: the content scrolls
    // under it, blurred; same edge colour and shadow, content capped at 520.
    final bar = DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  GameColors.bgDeep.withValues(alpha: 0.70),
                  GameColors.panel.withValues(alpha: 0.45),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: GameColors.panelEdge.withValues(alpha: 0.8),
                ),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                // + the 16 px side padding, so the row lines up with the tab content.
                constraints: BoxConstraints(
                  maxWidth: homeMaxWidth(context) + 32,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/brand/logo.png',
                        width: 38,
                        height: 38,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: AppLocalizations.of(context).logoLabel,
                      ),
                      const SizedBox(width: 10),
                      // The title takes the free space and shrinks on narrow
                      // windows instead of overflowing; the star counter stays
                      // at the right edge of the column.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: GameText(
                              AppLocalizations.of(context).appTitle,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      // Narrow Windows window: the caption buttons take the
                      // top-right corner, so the star counter is hidden.
                      if (!(usesCustomTitleBar &&
                          MediaQuery.sizeOf(context).width < _starHideWidth))
                        StarCounter(value: stars),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The header doubles as the window's drag handle on Windows.
    return usesCustomTitleBar ? WindowDragArea(child: bar) : bar;
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GameColors.panel.withValues(alpha: 0.92),
            GameColors.bgDeep.withValues(alpha: 0.98),
          ],
        ),
        border: Border(
          top: BorderSide(color: GameColors.panelEdge.withValues(alpha: 0.8)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: homeMaxWidth(context) + 8),
          child: Row(
            children: [
              for (final (i, (icon, label)) in [
                (Icons.route_rounded, l.navLearn),
                (Icons.fitness_center_rounded, l.navPractice),
                (Icons.person_rounded, l.navProfile),
              ].indexed)
                Expanded(
                  child: _NavItem(
                    icon: icon,
                    label: label,
                    active: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: active ? null : onTap,
      semanticLabel: label,
      sound: SfxKind.tab,
      lift: 2,
      builder: (p, hover) => Transform.scale(
        scale: 1 - 0.05 * p,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 54,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: ShapeDecoration(
            shape: chamfer(10),
            gradient: active
                ? GameTone.gold.gradient
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: hover ? 0.08 : 0),
                      Colors.white.withValues(alpha: hover ? 0.04 : 0),
                    ],
                  ),
            shadows: active
                ? [
                    BoxShadow(
                      color: GameColors.yellow.withValues(alpha: 0.35),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon pops when its tab becomes active.
              TweenAnimationBuilder<double>(
                key: ValueKey(active),
                tween: Tween(begin: active ? 0.6 : 1, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, k, child) =>
                    Transform.scale(scale: k, child: child),
                child: Icon(
                  icon,
                  size: 22,
                  color: active ? GameColors.ink : GameColors.textDim,
                ),
              ),
              const SizedBox(height: 2),
              GameText(
                label,
                size: 11,
                shadow: false,
                color: active ? GameColors.ink : GameColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
