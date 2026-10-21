import 'package:flutter/material.dart';

import '../../content/content_repo.dart';
import '../../input/midi_input.dart';
import '../../l10n/app_localizations.dart';
import '../../src/rust/api/practice.dart';
import '../../ui/game/game_theme.dart';
import '../../ui/game/game_widgets.dart';
import '../../ui/staff/staff_painter.dart' show Staves;
import '../practice_stage.dart';
import 'practice_service.dart';

/// Builds the playable stage for a tune; tests swap in a fake (Rust is not
/// loaded in `flutter test`).
typedef TuneStageBuilder = Widget Function(
  BuildContext context,
  StageDef stage,
  String songJson,
  void Function(ResultView) onFinished,
  VoidCallback onExit,
);

enum _Phase { loading, generating, playing, done, error }

/// Practice mode for one node (docs/specs/practice-mode.md, D28): loads the
/// melody model with download progress, generates a tune that passed the
/// rubric for the node's taught set, plays it with the usual stage UI and
/// offers another one. Tunes are labelled "Generated", give no stars or
/// course progress, and are never saved.
class GeneratedPracticePage extends StatefulWidget {
  const GeneratedPracticePage({
    super.key,
    required this.node,
    required this.title,
    required this.service,
    required this.midi,
    this.stageBuilder,
  });

  final PracticeNodeDef node;
  final String title;
  final PracticeService service;
  final MidiInput midi;
  final TuneStageBuilder? stageBuilder;

  @override
  State<GeneratedPracticePage> createState() => _GeneratedPracticePageState();
}

class _GeneratedPracticePageState extends State<GeneratedPracticePage> {
  _Phase _phase = _Phase.loading;
  double _progress = 0;
  GeneratedTune? _tune;
  ResultView? _result;
  String? _error;
  String _mode = 'wait';
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _another());
  }

  Future<void> _another() async {
    final l = AppLocalizations.of(context);
    final gen = widget.service.generator;
    if (!gen.supported) {
      setState(() {
        _phase = _Phase.error;
        _error = l.practiceNotYet;
      });
      return;
    }
    setState(() {
      _phase = _Phase.loading;
      _result = null;
      _error = null;
    });
    try {
      await gen.prepare(
        onProgress: (f) => mounted ? setState(() => _progress = f) : null,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = l.practiceModelError;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.generating);
    try {
      final tune = await widget.service.next(widget.node);
      if (!mounted) return;
      debugPrint(
        'practice: tune in ${tune.elapsed.inMilliseconds} ms '
        '(${tune.attempts} rounds, ${tune.rejected} refused by the rubric)',
      );
      setState(() {
        _tune = tune;
        _phase = _Phase.playing;
        _run++;
      });
    } catch (_) {
      // Rubric refused every candidate (or decoding failed): never show one.
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = l.practiceFailed;
        });
      }
    }
  }

  void _again() => setState(() {
    _result = null;
    _phase = _Phase.playing;
    _run++;
  });

  String get _hand => switch (widget.node.hands) {
    'BOTH' => 'both',
    final h => h,
  };

  Staves get _staves => switch (widget.node.hands) {
    'RH' => Staves.treble,
    'LH' => Staves.bass,
    _ => Staves.grand,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StagePalette.bgTop,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _body(context)),
            if (_phase == _Phase.playing || _phase == _Phase.done)
              const Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: IgnorePointer(child: Center(child: GeneratedBadge())),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = AppLocalizations.of(context);
    void exit() => Navigator.of(context).pop();
    switch (_phase) {
      case _Phase.playing:
      case _Phase.done:
        final stage = StageDef(type: _mode, hand: _hand);
        final song = _tune!.songJson;
        void finished(ResultView r) => setState(() {
          _result = r;
          _phase = _Phase.done;
        });
        return Stack(
          children: [
            Positioned.fill(
              child: KeyedSubtree(
                key: ValueKey(_run),
                child:
                    widget.stageBuilder?.call(
                      context,
                      stage,
                      song,
                      finished,
                      exit,
                    ) ??
                    PracticeStage(
                      stage: stage,
                      songJson: song,
                      midi: widget.midi,
                      failedAttempts: 0,
                      onFinished: finished,
                      staves: _staves,
                      tempo: 1,
                      onTempo: (_) {},
                      onRestart: _again,
                      onExit: exit,
                      instruction: l.practiceNoStars,
                    ),
              ),
            ),
            if (_phase == _Phase.done && _result != null)
              Positioned.fill(child: _donePanel(l, _result!, exit)),
          ],
        );
      case _Phase.loading:
      case _Phase.generating:
        final loading = _phase == _Phase.loading;
        return _panel(
          children: [
            Text(
              loading ? l.practiceLoading : l.practiceGenerating,
              textAlign: TextAlign.center,
              style: _textStyle,
            ),
            const SizedBox(height: 16),
            if (loading) ...[
              GameProgressBar(value: _progress, height: 10),
              const SizedBox(height: 8),
              Text(
                l.practiceDownload((_progress * 100).round()),
                style: const TextStyle(color: GameColors.textDim),
              ),
            ] else
              const LinearProgressIndicator(color: GameColors.cyan),
          ],
          exit: exit,
        );
      case _Phase.error:
        return _panel(
          children: [
            Text(_error ?? '', textAlign: TextAlign.center, style: _textStyle),
            const SizedBox(height: 16),
            if (widget.service.generator.supported)
              GameButton(
                label: l.retry.toUpperCase(),
                onTap: _another,
                tone: GameTone.green,
              ),
          ],
          exit: exit,
        );
    }
  }

  static const _textStyle = TextStyle(
    color: GameColors.text,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  Widget _donePanel(AppLocalizations l, ResultView r, VoidCallback exit) {
    return ColoredBox(
      color: Colors.black54,
      child: _panel(
        exit: exit,
        children: [
          Text(
            l.practiceNotesHit(r.notesHit, r.notesTotal),
            textAlign: TextAlign.center,
            style: _textStyle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            l.practiceNoStars,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GameColors.textDim),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final (m, label) in [
                ('wait', l.practiceWait),
                ('play_along', l.practicePlayAlong),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _mode == m,
                  onSelected: (_) => setState(() => _mode = m),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GameButton(
            label: l.practiceAnother.toUpperCase(),
            icon: Icons.casino_rounded,
            onTap: _another,
            tone: GameTone.green,
          ),
          const SizedBox(height: 10),
          GameButton(
            label: l.practiceAgain.toUpperCase(),
            icon: Icons.replay_rounded,
            onTap: _again,
            tone: GameTone.wood,
          ),
        ],
      ),
    );
  }

  Widget _panel({required List<Widget> children, required VoidCallback exit}) {
    return MenuBackground(
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
              child: GamePanel(
                title: widget.title,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 12,
            child: GameRoundButton(
              icon: Icons.close_rounded,
              onTap: exit,
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

/// "Generated" label on every practice tune (D28).
class GeneratedBadge extends StatelessWidget {
  const GeneratedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: GameColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GameColors.cyan),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: GameColors.cyan),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).generatedBadge,
            style: const TextStyle(
              color: GameColors.cyan,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
