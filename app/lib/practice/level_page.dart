import 'dart:convert';

import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import 'practice_stage.dart';

/// Runs a level's stages in order: scenes (captions until the Phase 2 player),
/// then playable stages graded by the core. Wait stages repeat `repeats`
/// times; the "Completed" card follows the last repeat. See
/// docs/specs/practice-screen.md.
class LevelPage extends StatefulWidget {
  const LevelPage({
    super.key,
    required this.repo,
    required this.level,
    required this.midi,
  });

  final ContentRepo repo;
  final LevelDef level;
  final MidiInput midi;

  @override
  State<LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends State<LevelPage> {
  int _index = 0;
  int _attempt = 0; // failed attempts on the current stage
  int _repeat = 0; // completed repeats of the current stage
  int _run = 0; // bumps to restart a stage widget
  double? _tempo; // tempo picked in the pause menu
  bool? _keyboard; // user override for the on-screen keyboard
  ResultView? _result;
  final _bestStars = <int, int>{};
  String? _midiLabel;

  @override
  void initState() {
    super.initState();
    _connectMidi(quiet: true);
  }

  /// Connects Web MIDI (the browser may ask for permission the first time).
  Future<void> _connectMidi({bool quiet = false}) async {
    final ok = await widget.midi.start();
    if (!mounted) return;
    final names = widget.midi.deviceNames;
    setState(
      () => _midiLabel = ok && names.isNotEmpty ? names.join(', ') : null,
    );
    if (!quiet && _midiLabel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'No MIDI keyboard found. Plug it in and try again.'
                : 'Web MIDI is not available in this browser.',
          ),
        ),
      );
    }
  }

  StageDef get _stage => widget.level.stages[_index];
  bool get _last => _index == widget.level.stages.length - 1;

  void _next() => setState(() {
    if (_last) {
      Navigator.of(context)
          .pop(_bestStars.values.fold<int>(3, (a, b) => b < a ? b : a));
      return;
    }
    _index++;
    _attempt = 0;
    _repeat = 0;
    _tempo = null;
    _result = null;
    _run++;
  });

  void _retry() => setState(() {
    if (_result != null && !_result!.passed) _attempt++;
    _repeat = 0;
    _result = null;
    _run++;
  });

  void _restart() => setState(() {
    _repeat = 0;
    _result = null;
    _run++;
  });

  void _setTempo(double t) => setState(() {
    _tempo = t;
    _result = null;
    _run++;
  });

  void _finished(ResultView r) => setState(() {
    if (r.passed) {
      final best = _bestStars[_index] ?? 0;
      if (r.stars > best) _bestStars[_index] = r.stars;
      // Wait stages repeat automatically until the counter is full.
      if (_repeat + 1 < _stage.repeats) {
        _repeat++;
        _run++;
        return;
      }
      _repeat = _stage.repeats;
    }
    _result = r;
    Sfx.play(r.passed ? SfxKind.win : SfxKind.lose);
  });

  String _songTitle(String? id) {
    final json = id == null ? null : widget.repo.songJson[id];
    if (json == null) return '';
    return (jsonDecode(json) as Map<String, dynamic>)['title'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    // Keyboard: the lesson's default, hidden on short screens, user can override.
    final roomy = MediaQuery.sizeOf(context).height >= 560;
    final showKeyboard = _keyboard ?? (widget.level.keyboard && roomy);
    return Scaffold(
      backgroundColor: StagePalette.bgTop,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _stageBody(repo, showKeyboard)),
            if (_result != null)
              Positioned.fill(child: _resultScreen(context, _result!)),
          ],
        ),
      ),
    );
  }

  Widget _stageBody(ContentRepo repo, bool showKeyboard) {
    final s = _stage;
    if (s.type == 'animation') {
      final scene = repo.scenes[s.scene];
      final lines = scene == null ? const <String>[] : sceneCaptions(scene);
      return _InfoStage(
        title: repo.t(widget.level.title),
        lines: [
          for (final l in lines) repo.t(l),
          '(Animated scene arrives with the Phase 2 scene player.)',
        ],
        onContinue: _next,
        onExit: () => Navigator.of(context).pop(),
      );
    }
    if (!s.isPlayable || repo.songJson[s.score] == null) {
      return _InfoStage(
        title: s.type,
        lines: const ['Not available yet.'],
        onContinue: _next,
        onExit: () => Navigator.of(context).pop(),
      );
    }
    return PracticeStage(
      key: ValueKey('$_index-$_run'),
      stage: s,
      songJson: repo.songJson[s.score]!,
      midi: widget.midi,
      failedAttempts: _attempt,
      onFinished: _finished,
      staves: stavesForUi(widget.level.ui),
      tempo: _tempo ?? s.tempo,
      onTempo: _setTempo,
      onRestart: _restart,
      onExit: () => Navigator.of(context).pop(),
      repeatDone: _index,
      repeatTotal: widget.level.stages.length,
      showKeyboard: showKeyboard,
      onToggleKeyboard: () => setState(() => _keyboard = !showKeyboard),
      midiLabel: _midiLabel,
      onConnectMidi: _connectMidi,
    );
  }

  /// Round medallion with a count-up value and a progress ring.
  Widget _stat(
    IconData icon,
    String label,
    double value,
    String Function(double) format,
    double fraction,
    int order,
  ) {
    final delay = Duration(milliseconds: 900 + 150 * order);
    return PopIn(
      delay: delay,
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GameColors.panel,
              border: Border.all(color: GameColors.panelEdge, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(GameColors.yellow),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: GameColors.yellow, size: 24),
                    CountUp(
                      value: value,
                      format: format,
                      size: 18,
                      delay: delay,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GameText(label, size: 14, color: GameColors.textDim),
        ],
      ),
    );
  }

  Widget _resultScreen(BuildContext context, ResultView r) {
    final s = _stage;
    // Reference formulas live in the core (session.rs): notes hit/total,
    // timing from the mean and spread of errors, assists = tempo used.
    final playAlong = s.type == 'play_along';
    final notesFrac = r.notesTotal == 0 ? 0.0 : r.notesHit / r.notesTotal;
    final title = _songTitle(s.score);
    String pct(double v) => '${v.round()}%';
    final hint = playAlong
        ? 'Hit ${(r.threshold * 100).round()}% of the notes in each part to pass.'
        : s.type == 'one_note'
        ? 'Play more than 80% of the notes.'
        : 'Play more than 80% of the notes before the hint appears.'
              '${r.suggestPractice ? ' Try a slower tempo.' : ''}';
    return ResultBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopIn(
                child: GameRibbon(
                  r.passed ? 'Completed!' : 'Almost there!',
                  tone: r.passed ? GameTone.green : GameTone.red,
                  fontSize: 36,
                ),
              ),
              if (title.isNotEmpty)
                SlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GameText(title, size: 20, color: GameColors.cyan),
                  ),
                ),
              const SizedBox(height: 12),
              // Stars fill continuously (e.g. half a star), as in the reference.
              StarRow(
                stars: r.starsExact,
                delay: const Duration(milliseconds: 300),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 28,
                runSpacing: 12,
                children: [
                  _stat(
                    Icons.music_note_rounded,
                    'NOTES',
                    r.notesHit.toDouble(),
                    (v) => '${v.round()}/${r.notesTotal}',
                    notesFrac,
                    0,
                  ),
                  if (playAlong) ...[
                    _stat(
                      Icons.timer_rounded,
                      'TIMING',
                      r.timing * 100,
                      pct,
                      r.timing,
                      1,
                    ),
                    _stat(
                      Icons.support_rounded,
                      'ASSISTS',
                      r.assists * 100,
                      pct,
                      r.assists,
                      2,
                    ),
                  ],
                ],
              ),
              if (!r.passed)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SlideIn(
                delay: const Duration(milliseconds: 1300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GameRoundButton(
                      icon: Icons.replay_rounded,
                      onTap: _retry,
                      tone: GameTone.blue,
                      size: 64,
                      tooltip: 'Retry',
                    ),
                    const SizedBox(width: 18),
                    GameButton(
                      label: r.passed ? 'NEXT' : 'LOCKED',
                      icon: r.passed
                          ? Icons.chevron_right_rounded
                          : Icons.lock_rounded,
                      onTap: r.passed ? _next : null,
                      tone: GameTone.green,
                      fontSize: 26,
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

class _InfoStage extends StatelessWidget {
  const _InfoStage({
    required this.title,
    required this.lines,
    required this.onContinue,
    required this.onExit,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onContinue;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return MenuBackground(
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
              child: PopIn(
                from: 0.6,
                child: GamePanel(
                  title: title,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            l,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: GameColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      GameButton(
                        label: 'CONTINUE',
                        onTap: onContinue,
                        tone: GameTone.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 12,
            child: GameRoundButton(
              icon: Icons.close_rounded,
              onTap: onExit,
              tone: GameTone.red,
              size: 48,
              tooltip: 'Exit',
            ),
          ),
        ],
      ),
    );
  }
}
