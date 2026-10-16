import 'dart:convert';

import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
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
      repeatDone: _repeat,
      repeatTotal: s.repeats,
      showKeyboard: showKeyboard,
      onToggleKeyboard: () => setState(() => _keyboard = !showKeyboard),
    );
  }

  Widget _stat(IconData icon, String label, String value, double fraction) {
    return Column(
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  strokeWidth: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(
                    StagePalette.current,
                  ),
                ),
              ),
              Icon(icon, color: StagePalette.current, size: 34),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _resultScreen(BuildContext context, ResultView r) {
    final s = _stage;
    final timing = r.meanAbsTimingMs;
    final windowMs = 150.0;
    final timingPct = timing == null
        ? 100.0
        : (100 * (1 - timing / windowMs)).clamp(0.0, 100.0);
    final title = _songTitle(s.score);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [StagePalette.bgTop, StagePalette.bgBottom],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              r.passed ? 'Completed!' : 'Almost there!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: StagePalette.current,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stat(
                  Icons.music_note_rounded,
                  'NOTES',
                  '${(r.hitRatio * 100).round()}%',
                  r.hitRatio,
                ),
                const SizedBox(width: 40),
                _stat(
                  Icons.timer_outlined,
                  'TIMING',
                  '${timingPct.round()}%',
                  timingPct / 100,
                ),
                const SizedBox(width: 40),
                _stat(Icons.support_outlined, 'ASSISTS', '100%', 1),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(
                    Icons.star_rounded,
                    size: 64,
                    color: i < r.stars ? StagePalette.current : Colors.white24,
                  ),
              ],
            ),
            if (!r.passed)
              Text(
                'Hit ${(r.threshold * 100).round()}% of the notes in each part to pass.'
                '${r.suggestPractice ? ' Try a slower tempo.' : ''}',
                style: const TextStyle(color: StagePalette.textDim),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _circleButton(Icons.replay_rounded, _retry, filled: true),
                const SizedBox(width: 16),
                _circleButton(
                  Icons.chevron_right_rounded,
                  r.passed ? _next : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(
    IconData icon,
    VoidCallback? onTap, {
    bool filled = false,
  }) {
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? const Color(0xFF14102A) : Colors.transparent,
          border: Border.all(
            color: enabled ? Colors.white70 : Colors.white24,
            width: 2.5,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
          size: 36,
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [StagePalette.bgTop, StagePalette.bgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 10,
            child: IconButton(
              onPressed: onExit,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.movie_filter_outlined,
                    size: 52,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: StagePalette.done,
                      foregroundColor: StagePalette.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 16,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: onContinue,
                    child: const Text(
                      'CONTINUE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
