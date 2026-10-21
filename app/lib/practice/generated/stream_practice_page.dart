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
import 'practice_stream.dart';
import 'song_feed.dart';

/// Builds the playable stage; tests swap in a fake (Rust is not loaded in
/// `flutter test`).
typedef StreamStageBuilder = Widget Function(
  BuildContext context,
  StageDef stage,
  SongFeed feed,
  void Function(ResultView) onFinished,
  VoidCallback onExit,
);

/// Endless practice setup (docs/specs/practice-mode.md): the learner picks
/// the level (a course node: its taught set bounds every note), hands, tempo,
/// note values and mode, then plays a stream the model writes while they
/// play.
class StreamSetupPage extends StatefulWidget {
  const StreamSetupPage({
    super.key,
    required this.repo,
    required this.generator,
    required this.midi,
    this.initialNode,
    this.stageBuilder,
  });

  final ContentRepo repo;
  final TuneGenerator generator;
  final MidiInput midi;

  /// `course/node` to preselect (the learner's next node).
  final String? initialNode;
  final StreamStageBuilder? stageBuilder;

  @override
  State<StreamSetupPage> createState() => _StreamSetupPageState();
}

/// Styles offered on the setup screen (model `STYLE_` tokens); null = any.
const practiceStyles = [
  null,
  'classical',
  'folk',
  'children',
  'pop',
  'jazz',
  'game',
];

class _StreamSetupPageState extends State<StreamSetupPage> {
  late final List<PracticeNodeDef> _nodes = [
    for (final c in widget.repo.courses)
      for (final n in c.nodes)
        if (widget.repo.practice['${c.id}/${n.id}'] case final d?
            when d.gen != null)
          d,
  ];

  /// Level (1–5, the taught set's difficulty) → the last node at that level
  /// in course order: the widest taught set the level allows.
  late final Map<int, PracticeNodeDef> _levels = {
    for (final n in _nodes) (n.gen!['level'] as num).toInt(): n,
  };
  late int _level = () {
    final start = _nodes.where((n) => n.key == widget.initialNode).firstOrNull;
    final lv = (start?.gen?['level'] as num?)?.toInt();
    return _levels.containsKey(lv) ? lv! : _levels.keys.first;
  }();
  String? _style;
  late String _hands;
  late double _bpm;
  late Set<String> _durs;
  String _mode = 'wait';

  PracticeNodeDef get _node => _levels[_level]!;

  @override
  void initState() {
    super.initState();
    _pick(_level);
  }

  void _pick(int level) {
    _level = level;
    final n = _node;
    final c = NodeChoices(n);
    final want = n.gen!['hands'] as String;
    _hands = c.hands.contains(want) ? want : c.hands.first;
    _bpm = (n.gen!['bpm'] as num).toDouble();
    _durs = {...c.durations};
  }

  String _styleName(AppLocalizations l, String? s) => switch (s) {
    'classical' => l.styleClassical,
    'folk' => l.styleFolk,
    'children' => l.styleChildren,
    'pop' => l.stylePop,
    'jazz' => l.styleJazz,
    'game' => l.styleGame,
    _ => l.styleAny,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NodeChoices(_node);
    final durs = [
      for (final d in c.durations)
        if (_durs.contains(d)) d,
    ];
    final fits =
        durs.isNotEmpty && fillsBar(durs, _node.gen!['time'] as String);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        t.toUpperCase(),
        style: const TextStyle(
          color: GameColors.cyan,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
    Widget chips<T>(
      List<(T, String)> items,
      bool Function(T) selected,
      void Function(T) onTap, {
      TextStyle? style,
    }) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, text) in items)
          GameChip(
            label: text,
            selected: selected(v),
            style: style,
            onTap: () => setState(() => onTap(v)),
          ),
      ],
    );
    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
                  child: GamePanel(
                    title: l.endlessPractice,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.endlessPracticeDesc,
                          style: const TextStyle(color: GameColors.textDim),
                        ),
                        label(l.setupLevel),
                        chips<int>(
                          [for (final lv in _levels.keys) (lv, '$lv')],
                          (lv) => lv == _level,
                          _pick,
                        ),
                        label(l.setupStyle),
                        chips<String?>(
                          [
                            for (final s in practiceStyles)
                              (s, _styleName(l, s)),
                          ],
                          (s) => s == _style,
                          (s) => _style = s,
                        ),
                        label(l.setupHands),
                        chips<String>(
                          [
                            for (final h in c.hands)
                              (
                                h,
                                switch (h) {
                                  'RH' => l.handRight,
                                  'LH' => l.handLeft,
                                  _ => l.handBoth,
                                },
                              ),
                          ],
                          (h) => h == _hands,
                          (h) => _hands = h,
                        ),
                        label(l.setupTempo(_bpm.round())),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: GameColors.yellow,
                            inactiveTrackColor: Colors.black38,
                            thumbColor: GameColors.yellow,
                            overlayColor: GameColors.yellow.withValues(
                              alpha: 0.15,
                            ),
                            activeTickMarkColor: Colors.transparent,
                            inactiveTickMarkColor: Colors.transparent,
                          ),
                          child: Slider(
                            value: _bpm,
                            min: 40,
                            max: 160,
                            divisions: 24,
                            onChanged: (v) => setState(() => _bpm = v),
                          ),
                        ),
                        label(l.setupNoteValues),
                        chips<String>(
                          [for (final d in c.durations) (d, durGlyph(d))],
                          _durs.contains,
                          (d) => _durs.contains(d)
                              ? _durs.remove(d)
                              : _durs.add(d),
                          style: const TextStyle(
                            fontFamily: 'Bravura',
                            fontSize: 22,
                            height: 1.1,
                          ),
                        ),
                        if (!fits)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              l.noteValuesInvalid,
                              style: const TextStyle(color: GameColors.danger),
                            ),
                          ),
                        label(l.setupMode),
                        chips<String>(
                          [
                            ('wait', l.practiceWait),
                            ('play_along', l.practicePlayAlong),
                          ],
                          (m) => m == _mode,
                          (m) => _mode = m,
                        ),
                        const SizedBox(height: 22),
                        GameButton(
                          label: l.play.toUpperCase(),
                          icon: Icons.play_arrow_rounded,
                          fontSize: 20,
                          height: 54,
                          onTap: fits
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StreamPracticePage(
                                      settings: StreamSettings(
                                        node: _node,
                                        hands: _hands,
                                        bpm: _bpm.round(),
                                        durations: durs,
                                        mode: _mode,
                                        style: _style,
                                      ),
                                      generator: widget.generator,
                                      midi: widget.midi,
                                      title: l.levelN(_level),
                                      stageBuilder: widget.stageBuilder,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 12,
                child: GameRoundButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                  tone: GameTone.red,
                  size: 48,
                  tooltip: l.exit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable chip in the game style (chamfered, yellow when picked), like
/// the task rows of the node sheet.
class GameChip extends StatelessWidget {
  const GameChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.style,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      burst: false,
      builder: (p, hover) => Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          shape: chamfer(
            8,
            side: BorderSide(
              color: selected ? GameColors.yellow : GameColors.panelEdge,
              width: selected ? 2 : 1,
            ),
          ),
          color: selected
              ? GameColors.yellow.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: hover ? 0.2 : 0.3),
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: style?.fontFamily == 'Bravura'
              ? NoteGlyph(
                  label,
                  color: selected ? GameColors.yellow : Colors.white,
                )
              : Text(
                  label,
                  style: (style ?? const TextStyle()).copyWith(
                    color: selected ? GameColors.yellow : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: style?.fontSize ?? 15,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Note value glyphs on the chips: SMuFL metronome-mark notes in Bravura
/// (the app's music font), e.g. `4.` = quarter + augmentation dot.
String durGlyph(String d) {
  final base = switch (d.replaceAll('.', '')) {
    '1' => '',
    '2' => '',
    '4' => '',
    '8' => '',
    '16' => '',
    _ => '', // 32nd
  };
  return base + '' * (d.length - d.replaceAll('.', '').length);
}

enum _Phase { loading, generating, playing, done, error }

/// Plays an endless generated stream with the usual stage UI. Labelled
/// "Generated"; no stars, no course progress, nothing saved (D28).
class StreamPracticePage extends StatefulWidget {
  const StreamPracticePage({
    super.key,
    required this.settings,
    required this.generator,
    required this.midi,
    required this.title,
    this.stageBuilder,
    this.stream,
  });

  final StreamSettings settings;
  final TuneGenerator generator;
  final MidiInput midi;
  final String title;
  final StreamStageBuilder? stageBuilder;

  /// Injected in tests; built from [settings] otherwise.
  final PracticeStream? stream;

  @override
  State<StreamPracticePage> createState() => _StreamPracticePageState();
}

class _StreamPracticePageState extends State<StreamPracticePage> {
  _Phase _phase = _Phase.loading;
  double _progress = 0;
  SongFeed? _feed;
  ResultView? _result;
  String? _error;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final gen = widget.generator;
    void fail(String e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e;
        });
      }
    }

    if (!gen.supported) return fail(l.practiceNotYet);
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
      return fail(l.practiceModelError);
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.generating);
    final stream = widget.stream ?? PracticeStream(gen, widget.settings);
    try {
      final feed = await stream.start();
      if (!mounted) return;
      debugPrint(
        'practice stream: first chunk in ${stream.chunkMs.first} ms '
        '(${stream.rejected} refused by the rubric)',
      );
      feed.addListener(
        () => debugPrint(
          'practice stream: ${stream.chunks} chunks, last '
          '${stream.chunkMs.last} ms, ended ${feed.ended}',
        ),
      );
      setState(() {
        _feed = feed;
        _phase = _Phase.playing;
        _run++;
      });
    } catch (_) {
      fail(l.practiceFailed);
    }
  }

  Staves get _staves => switch (widget.settings.hands) {
    'RH' => Staves.treble,
    'LH' => Staves.bass,
    _ => Staves.grand,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void exit() => Navigator.of(context).pop();
    return Scaffold(
      backgroundColor: StagePalette.bgTop,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _body(l, exit)),
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

  Widget _body(AppLocalizations l, VoidCallback exit) {
    switch (_phase) {
      case _Phase.playing:
      case _Phase.done:
        final s = widget.settings;
        final stage = StageDef(
          type: s.mode,
          hand: s.hands == 'BOTH' ? 'both' : s.hands,
        );
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
                      _feed!,
                      finished,
                      exit,
                    ) ??
                    PracticeStage(
                      stage: stage,
                      songJson: _feed!.json,
                      feed: _feed,
                      midi: widget.midi,
                      failedAttempts: 0,
                      onFinished: finished,
                      staves: _staves,
                      tempo: 1,
                      onTempo: (_) {},
                      onRestart: _start,
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
          exit: exit,
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
        );
      case _Phase.error:
        return _panel(
          exit: exit,
          children: [
            Text(_error ?? '', textAlign: TextAlign.center, style: _textStyle),
            const SizedBox(height: 16),
            if (widget.generator.supported)
              GameButton(
                label: l.retry.toUpperCase(),
                onTap: _start,
                tone: GameTone.green,
              ),
          ],
        );
    }
  }

  static const _textStyle = TextStyle(
    color: GameColors.text,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  /// Shown only when the stream could not continue (the learner normally
  /// leaves with the close button).
  Widget _donePanel(AppLocalizations l, ResultView r, VoidCallback exit) {
    return ColoredBox(
      color: Colors.black54,
      child: _panel(
        exit: exit,
        children: [
          Text(l.streamEnded, textAlign: TextAlign.center, style: _textStyle),
          const SizedBox(height: 8),
          Text(
            l.practiceNotesHit(r.notesHit, r.notesTotal),
            textAlign: TextAlign.center,
            style: _textStyle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 16),
          GameButton(
            label: l.practiceAgain.toUpperCase(),
            icon: Icons.replay_rounded,
            onTap: _start,
            tone: GameTone.green,
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

/// A Bravura note glyph centred in a fixed box. SMuFL glyphs hang from the
/// baseline with the stem (and flag) up, so a plain Text sits low and the
/// flag spills past the advance width; this places the notehead by the
/// baseline and centres the whole note including its flag.
class NoteGlyph extends StatelessWidget {
  const NoteGlyph(this.glyph, {super.key, required this.color});

  final String glyph;
  final Color color;

  static const _box = 30.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(_box),
    painter: _NotePainter(glyph, color),
  );
}

class _NotePainter extends CustomPainter {
  _NotePainter(this.glyph, this.color);

  final String glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const em = 26.0;
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontFamily: 'Bravura', fontSize: em, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    // Flags (8th and shorter) draw about a quarter em right of the advance.
    final flagged = const {'', '', ''}.contains(glyph[0]);
    final ink = tp.width + (flagged ? em * 0.24 : 0);
    // Ink above the baseline: a stemmed note about 0.7 em, a whole note
    // (no stem) only its head, about 0.28 em. Centre that span.
    final h = glyph.startsWith('') ? em * 0.28 : em * 0.7;
    final top = (size.height - h) / 2;
    tp.paint(canvas, Offset((size.width - ink) / 2, top + h - baseline));
  }

  @override
  bool shouldRepaint(_NotePainter old) =>
      old.glyph != glyph || old.color != color;
}
