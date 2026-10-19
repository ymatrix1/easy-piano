import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import 'practice_stage.dart';
import 'result_screen.dart';

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
                ? AppLocalizations.of(context).midiNotFound
                : AppLocalizations.of(context).midiUnavailable,
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
              Positioned.fill(
                child: ResultScreen(
                  result: _result!,
                  stageType: _stage.type,
                  songTitle: _songTitle(_stage.score),
                  onRetry: _retry,
                  onNext: _next,
                ),
              ),
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
          AppLocalizations.of(context).scenePending,
        ],
        onContinue: _next,
        onExit: () => Navigator.of(context).pop(),
      );
    }
    if (!s.isPlayable || repo.songJson[s.score] == null) {
      return _InfoStage(
        title: s.type,
        lines: [AppLocalizations.of(context).notAvailableYet],
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
                        label: AppLocalizations.of(context).continueButton
                            .toUpperCase(),
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
              tooltip: AppLocalizations.of(context).exit,
            ),
          ),
        ],
      ),
    );
  }
}
