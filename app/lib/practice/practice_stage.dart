import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;

import '../audio/piano_synth.dart';
import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/key_geometry.dart';
import '../ui/keyboard_painter.dart';
import '../ui/metronome_icon.dart';
import '../ui/staff/staff_note.dart';
import '../ui/staff/staff_painter.dart';

/// FRB maps i64 to int on native and BigInt on web.
int _int(Object v) => v is BigInt ? v.toInt() : v as int;

/// Practice screen palette (ours; see docs/specs/practice-screen.md).
abstract final class StagePalette {
  static const bgTop = Color(0xFF6E2CF2);
  static const bgBottom = Color(0xFF7B3BFF);
  static const band = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16131F);
  static const current = Color(0xFFF57C00); // readable on the white band
  static const keyTarget = Color(0xFFFFB400);
  static const currentGlow = Color(0xFFFFC266);
  static const badgeCurrent = Color(0xFFFF8A1F);
  static const done = Color(0xFF19C6DE);
  static const miss = Color(0xFFFF4D6A);
  static const badge = Color(0xFF5B21B6);
  static const playBar = Color(0xFF19E3F0);
  static const burst = Color(0xFF7FE7FF);
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xCCFFFFFF);
}

/// Staff layout from a level's `ui` field.
Staves stavesForUi(String ui) => switch (ui) {
  'treble' => Staves.treble,
  'bass' => Staves.bass,
  _ => Staves.grand,
};

/// One playable stage (wait / play_along / one_note), graded by the Rust core.
///
/// Wait: the exercise is laid out on a still page; the highlight jumps to the
/// next note on a correct press and the page slides (1 s) only past 72% of
/// the width. Play-along: notes scroll toward a cyan bar right after the clef.
/// See docs/specs/practice-screen.md.
///
/// Clock: until the audio engine lands (bean piano-k0ht), song time comes from
/// the same monotonic clock as MIDI event timestamps, so grading is consistent.
class PracticeStage extends StatefulWidget {
  const PracticeStage({
    super.key,
    required this.stage,
    required this.songJson,
    required this.midi,
    required this.failedAttempts,
    required this.onFinished,
    required this.staves,
    required this.tempo,
    required this.onTempo,
    required this.onRestart,
    required this.onExit,
    this.instruction = 'Play the following notes',
    this.repeatDone = 0,
    this.repeatTotal = 1,
    this.showKeyboard = true,
    this.onToggleKeyboard,
    this.midiLabel,
    this.onConnectMidi,
  });

  final StageDef stage;
  final String songJson;
  final MidiInput midi;
  final int failedAttempts;
  final void Function(ResultView result) onFinished;
  final Staves staves;

  /// Effective tempo factor (stage tempo or the one picked in the pause menu).
  final double tempo;
  final void Function(double tempo) onTempo;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final String instruction;
  final int repeatDone;
  final int repeatTotal;

  /// The on-screen keyboard is optional (MIDI players may hide it).
  final bool showKeyboard;
  final VoidCallback? onToggleKeyboard;

  /// Connected MIDI device name, or null when none; tapping connects.
  final String? midiLabel;
  final VoidCallback? onConnectMidi;

  @override
  State<PracticeStage> createState() => _PracticeStageState();
}

class _PracticeStageState extends State<PracticeStage>
    with TickerProviderStateMixin {
  static const _low =
      36; // C2: middle C sits in the centre (2 octaves each side)
  static const _high = 84; // C6
  static const _maxPpb = 120.0; // pixels per beat
  static const _minPpb = 70.0;
  static const _waitAnchor = 0.10; // page start, as a fraction of the width
  static const _pageTurnAt =
      0.60; // next note past this fraction → slide (reference)
  static const _playLine = 0.12; // play bar right after the clef

  late final PracticeSession _session;
  late final List<StaffNote> _notes;
  late final List<int> _noteTarget; // staff note index → target index
  late final List<int>
  _targetFirstNote; // target index → first staff note index
  late final double _beatsPerBar;
  late final double _usPerBeat;
  late final List<TargetView> _initialTargets;
  final _scroll = ValueNotifier<double>(0);
  final _marks = ValueNotifier<int>(0);
  final _pressed = ValueNotifier<Set<int>>({});
  final _hint = ValueNotifier<Set<int>>({});
  final _pointerPitch = <int, int>{};
  final _bursts = <HitBurst>[];
  List<int> _targetStates = const [];
  late final Ticker _ticker;
  late final AnimationController _pageAnim;
  Animation<double>? _pageTween;
  StreamSubscription<NoteEvent>? _sub;
  late double _startMs; // stage time zero on the input clock
  double? _pausedAtMs;
  FrameView? _frame;
  double _staffWidth = 1200;
  double _ppb = _maxPpb;
  double _cursorSinceSec = 0; // when the current wait note became current
  double? _hintSinceSec; // when the hint for the current note appeared
  bool _finished = false;
  bool _wasCountIn = false;

  /// Notes the app plays with the student in play-along (other hand + ACC).
  List<NoteView> _companion = const [];

  /// Pre-listen: the app plays the passage first; input is ignored meanwhile.
  bool _demo = false;
  double _demoStartMs = 0;
  int _demoIndex = 0;

  bool get _playAlong => widget.stage.type == 'play_along';
  bool get _paused => _pausedAtMs != null;

  @override
  void initState() {
    super.initState();
    final info = inspectSong(json: widget.songJson);
    _beatsPerBar = info.beatsPerBar.toDouble();
    _usPerBeat = 60e6 / (info.bpm * widget.tempo);
    _session = PracticeSession.create(
      songJson: widget.songJson,
      mode: widget.stage.type,
      input: 'midi',
      hand: widget.stage.hand,
      tempo: widget.tempo,
      passRatio: widget.stage.pass,
      failedAttempts: widget.failedAttempts,
    );
    _initialTargets = _session.targets();
    _notes = [];
    _noteTarget = [];
    _targetFirstNote = [];
    for (var i = 0; i < _initialTargets.length; i++) {
      final t = _initialTargets[i];
      _targetFirstNote.add(_notes.length);
      for (var k = 0; k < t.pitches.length; k++) {
        final p = t.pitches[k];
        final f = k < t.fingers.length && t.fingers[k] > 0
            ? t.fingers[k]
            : null;
        _notes.add(StaffNote(p, t.beat, t.beats, leftHand: p < 60, finger: f));
        _noteTarget.add(i);
      }
    }
    _targetStates = [for (final t in _initialTargets) t.state];
    _scroll.value = _playAlong ? -_countInBeats : 0;
    _pageAnim =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            final tw = _pageTween;
            if (tw != null) _scroll.value = tw.value;
          });
    if (_playAlong) {
      _companion = companion(
        songJson: widget.songJson,
        hand: widget.stage.hand,
      );
    }
    pianoSynth.load();
    if (widget.stage.preListen && widget.failedAttempts == 0) {
      _startDemo();
    } else {
      _begin();
    }
    _sub = widget.midi.events.listen(
      (e) => _onNote(e.pitch, e.on, e.timestampMs),
    );
    _ticker = createTicker((_) => _tick())..start();
  }

  double get _totalBeats => _initialTargets.isEmpty
      ? 1
      : _initialTargets.last.beat + _initialTargets.last.beats;

  /// Wait mode fits the whole exercise on one page when it can.
  void _fitPage(double width) {
    _staffWidth = width;
    if (_playAlong) return;
    final usable = (0.92 - _waitAnchor) * width;
    _ppb = (usable / _totalBeats).clamp(_minPpb, _maxPpb);
  }

  int _usAt(double ms) => ((ms - _startMs) * 1000).round();

  double get _msPerBeat => _usPerBeat / 1000;

  /// Count-in: whole bars, at least 2.5 s (the reference's look-ahead), so
  /// the first note glides in from the right instead of starting at once.
  double get _countInBeats {
    var beats = _beatsPerBar.toDouble();
    while (beats * _msPerBeat < 2500) {
      beats += _beatsPerBar;
    }
    return beats;
  }

  /// Starts the graded part. Play-along gets a one-bar count-in.
  void _begin() {
    _startMs =
        widget.midi.now() + (_playAlong ? _countInBeats * _msPerBeat : 0);
    if (_playAlong) _scheduleBacking(-_countInBeats);
  }

  /// Schedules count-in clicks, the companion notes and, when the metronome
  /// is on, a click on every beat. [fromBeat] is song time in beats.
  void _scheduleBacking(double fromBeat) {
    final now = widget.midi.now();
    double inSec(double beat) => (_startMs + beat * _msPerBeat - now) / 1000;
    for (var b = fromBeat.ceilToDouble(); b < 0; b++) {
      pianoSynth.click(
        inSec(b),
        accent: (b + _beatsPerBar) % _beatsPerBar == 0,
      );
    }
    if (pianoSynth.metronome) {
      for (
        var b = math.max(0.0, fromBeat.ceilToDouble());
        b < _totalBeats;
        b++
      ) {
        pianoSynth.click(inSec(b), accent: b % _beatsPerBar == 0);
      }
    }
    for (final n in _companion) {
      if (n.beat < fromBeat) continue;
      if (n.partName == 'DRUMS') {
        pianoSynth.drum(n.pitch, inSec(n.beat));
        continue;
      }
      if (n.partName == 'BASS') {
        pianoSynth.bass(
          n.pitch,
          inSec(n.beat),
          n.beats * _msPerBeat / 1000 * 0.9,
          velocity: 90,
        );
        continue;
      }
      pianoSynth.schedule(
        n.pitch,
        inSec(n.beat),
        n.beats * _msPerBeat / 1000 * 0.95,
        velocity: 62,
        force: true,
      );
    }
  }

  /// Flips the metronome; reschedules backing from the current beat so the
  /// change is heard at once.
  void _toggleMetronome() {
    setState(() => pianoSynth.metronome = !pianoSynth.metronome);
    if (_demo || _paused || _finished) return;
    pianoSynth.stopAll();
    _scheduleBacking(_scroll.value);
  }

  /// Pre-listen: plays the passage while a beam walks over the notes.
  ///
  /// Samples must be decoded before scheduling, or the notes are silent; the
  /// beam waits for them too so sound and beam stay together.
  Future<void> _startDemo() async {
    _demo = true;
    _demoIndex = 0;
    _demoStartMs = double.infinity;
    await pianoSynth.load();
    if (!mounted || !_demo) return;
    _demoStartMs = widget.midi.now() + 400;
    final lead = 0.4;
    for (final t in _initialTargets) {
      for (final p in t.pitches) {
        pianoSynth.schedule(
          p,
          lead + t.beat * _msPerBeat / 1000,
          t.beats * _msPerBeat / 1000 * 0.95,
          force: true,
        );
      }
    }
    _startMs = widget.midi.now();
  }

  void _endDemo() {
    pianoSynth.stopAll();
    _demo = false;
    _demoIndex = 0;
    if (!_playAlong) {
      _pageTween = Tween(begin: _scroll.value, end: 0.0).animate(
        CurvedAnimation(parent: _pageAnim, curve: Curves.easeInOutCubic),
      );
      _pageAnim.forward(from: 0);
    }
    _cursorSinceSec = _nowSec;
    _begin();
    setState(() {});
  }

  double get _nowSec => widget.midi.now() / 1000;

  void _onNote(int pitch, bool on, double timestampMs) {
    on ? pianoSynth.noteOn(pitch) : pianoSynth.noteOff(pitch);
    final next = {..._pressed.value};
    on ? next.add(pitch) : next.remove(pitch);
    _pressed.value = next;
    if (_paused || _finished || _demo) return;
    final cursor = _frame?.cursor ?? 0;
    if (on &&
        !_playAlong &&
        cursor < _initialTargets.length &&
        !_initialTargets[cursor].pitches.contains(pitch)) {
      // Reference: a wrong key only gets a blue splash; it is not penalised.
      _bursts.add(
        HitBurst(
          beat: _initialTargets[cursor].beat,
          pitch: pitch,
          leftHand: pitch < 60,
          startSec: _nowSec,
          whole: _initialTargets[cursor].beats >= 4,
        ),
      );
    }
    _session.onNote(
      pitch: pitch,
      on_: on,
      tUs: PlatformInt64Util.from(_usAt(timestampMs)),
    );
  }

  void _pause() {
    pianoSynth.stopAll();
    setState(() => _pausedAtMs = widget.midi.now());
  }

  void _resume() => setState(() {
    // Shift stage time so the song continues where it was paused.
    _startMs += widget.midi.now() - _pausedAtMs!;
    _pausedAtMs = null;
    if (_playAlong && !_demo) _scheduleBacking(_scroll.value);
  });

  /// Wait mode: slide the page when the next note would run past the page edge.
  void _maybeTurnPage(int cursor) {
    if (_playAlong || cursor >= _initialTargets.length) return;
    final nextBeat = _initialTargets[cursor].beat;
    final x = (nextBeat - _scroll.value) * _ppb;
    if (_pageAnim.isAnimating) return;
    if (x > (_pageTurnAt - _waitAnchor) * _staffWidth) {
      // Reference: slide so the next note returns to the left margin, but
      // never past the point where the end of the piece is already in view.
      final lastVisible =
          _totalBeats - (0.92 - _waitAnchor) * _staffWidth / _ppb;
      final end = math.min(nextBeat, math.max(_scroll.value, lastVisible));
      if (end <= _scroll.value + 0.01) return;
      _pageTween = Tween(begin: _scroll.value, end: end).animate(
        CurvedAnimation(parent: _pageAnim, curve: Curves.easeInOutSine),
      );
      _pageAnim.forward(from: 0);
    }
  }

  void _tick() {
    if (_finished || _paused) return;
    if (_demo) {
      final beat = (widget.midi.now() - _demoStartMs) / _msPerBeat;
      var idx = 0;
      while (idx + 1 < _initialTargets.length &&
          _initialTargets[idx + 1].beat <= beat) {
        idx++;
      }
      if (idx != _demoIndex) {
        _demoIndex = idx;
        _maybeTurnPage(idx);
      }
      _marks.value++;
      if (beat > _totalBeats + 0.5) _endDemo();
      return;
    }
    final f = _session.tick(
      tUs: PlatformInt64Util.from(_usAt(widget.midi.now())),
    );
    if (_playAlong) {
      // The engine clock starts at 0; during the count-in scroll on wall time
      // so the first note glides in toward the bar.
      final us = _usAt(widget.midi.now());
      _scroll.value = us < 0 ? us / _usPerBeat : f.playheadBeat;
    }
    final targets = _session.targets();
    final states = [for (final t in targets) t.state];
    final now = _nowSec;
    var changed = false;
    for (var i = 0; i < states.length; i++) {
      if (states[i] != _targetStates[i]) {
        changed = true;
        if (states[i] == 1) {
          for (final p in targets[i].pitches) {
            _bursts.add(
              HitBurst(
                beat: targets[i].beat,
                pitch: p,
                leftHand: p < 60,
                startSec: now,
                whole: targets[i].beats >= 4,
              ),
            );
          }
        }
      }
    }
    _bursts.removeWhere((b) => now - b.startSec > HitBurst.durationSec);
    if (changed) _targetStates = states;
    final cursorMoved = _frame == null || f.cursor != _frame!.cursor;
    if (cursorMoved) {
      _maybeTurnPage(f.cursor);
      _cursorSinceSec = now;
    }
    // Repaint while bursts or the beam fade animate, or when marks change.
    if (changed ||
        _bursts.isNotEmpty ||
        cursorMoved ||
        now - _cursorSinceSec < 0.25 ||
        (_hintSinceSec != null && now - _hintSinceSec! < 0.25)) {
      _marks.value++;
    }
    if (f.hintActive && _hintSinceSec == null) _hintSinceSec = now;
    if (!f.hintActive) _hintSinceSec = null;
    final showKeys = _playAlong || f.hintActive;
    _hint.value = showKeys && f.cursor < targets.length
        ? {...targets[f.cursor].pitches}
        : {};
    final inCountIn = _scroll.value < 0;
    final countInChanged = inCountIn != _wasCountIn;
    _wasCountIn = inCountIn;
    if (_frame == null ||
        f.hits != _frame!.hits ||
        f.misses != _frame!.misses ||
        f.wrong != _frame!.wrong ||
        countInChanged ||
        _playAlong) {
      setState(() => _frame = f);
    } else {
      _frame = f;
    }
    final over = _playAlong
        ? _usAt(widget.midi.now()) > _int(_session.endUs())
        : f.done;
    if (over) {
      _finished = true;
      _ticker.stop();
      setState(() {});
      // Let the check mark / last hit show briefly before the result.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) widget.onFinished(_session.result());
      });
    }
  }

  Color _noteColor(int i) {
    final ti = _noteTarget[i];
    switch (_targetStates[ti]) {
      case 1:
        return StagePalette.done;
      case 2:
        return StagePalette.miss;
      default:
        return !_playAlong && ti == _activeIndex
            ? StagePalette.current
            : StagePalette.ink;
    }
  }

  /// Only the note to play next gets a badge; the others show a plain number.
  Color? _badgeColor(int i) {
    if (_playAlong) return null;
    return _noteTarget[i] == _activeIndex ? StagePalette.badgeCurrent : null;
  }

  /// Target highlighted now: the demo position during pre-listen, else the cursor.
  int get _activeIndex => _demo ? _demoIndex : (_frame?.cursor ?? 0);

  int? _currentNoteIndex() {
    if (_demo) {
      return _demoIndex < _targetFirstNote.length
          ? _targetFirstNote[_demoIndex]
          : null;
    }
    if (_playAlong) return null;
    final c = _frame?.cursor ?? 0;
    return c < _targetFirstNote.length ? _targetFirstNote[c] : null;
  }

  void _touchDown(int pointer, Offset p, Size size) {
    final pitch = KeyGeometry(
      lowPitch: _low,
      highPitch: _high,
      size: size,
    ).pitchAt(p);
    if (pitch == null) return;
    _pointerPitch[pointer] = pitch;
    _onNote(pitch, true, widget.midi.now());
  }

  void _touchUp(int pointer) {
    final pitch = _pointerPitch.remove(pointer);
    if (pitch != null) _onNote(pitch, false, widget.midi.now());
  }

  @override
  void dispose() {
    pianoSynth.stopAll();
    _ticker.dispose();
    _pageAnim.dispose();
    _sub?.cancel();
    _scroll.dispose();
    _marks.dispose();
    _pressed.dispose();
    _hint.dispose();
    super.dispose();
  }

  Widget _topBar() {
    final f = _frame;
    final total = _initialTargets.isEmpty ? 1 : _initialTargets.length;
    final judged = ((f?.hits ?? 0) + (f?.misses ?? 0)) / total;
    final waitPill = widget.repeatTotal > 1;
    final pillValue = _playAlong
        ? ((f?.playheadBeat ?? 0) / _totalBeats)
        : waitPill
        ? widget.repeatDone / widget.repeatTotal
        : judged;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 20, 0),
      child: Row(
        children: [
          // Paused: resume / restart / exit take the pause button's place in
          // the same bar, so nothing covers the staff or the bar itself.
          if (_paused) ...[
            SlideIn(
              offset: const Offset(-30, 0),
              child: GameRoundButton(
                icon: Icons.play_arrow_rounded,
                onTap: _resume,
                tone: GameTone.green,
                size: 46,
                tooltip: 'Resume',
              ),
            ),
            const SizedBox(width: 10),
            SlideIn(
              delay: const Duration(milliseconds: 60),
              offset: const Offset(-30, 0),
              child: GameRoundButton(
                icon: Icons.replay_rounded,
                onTap: widget.onRestart,
                tone: GameTone.blue,
                size: 46,
                tooltip: 'Restart',
              ),
            ),
            const SizedBox(width: 10),
            SlideIn(
              delay: const Duration(milliseconds: 120),
              offset: const Offset(-30, 0),
              child: GameRoundButton(
                icon: Icons.format_list_bulleted_rounded,
                onTap: widget.onExit,
                tone: GameTone.red,
                size: 46,
                tooltip: 'Exit to map',
              ),
            ),
          ] else ...[
            GameRoundButton(
              icon: Icons.pause_rounded,
              onTap: _pause,
              tone: GameTone.gold,
              size: 46,
              tooltip: 'Pause',
            ),
            const SizedBox(width: 14),
            Text(
              _demo
                  ? 'Listen first…'
                  : _playAlong
                  ? 'Play along · ${(widget.tempo * 100).round()}%'
                  : widget.instruction,
              style: const TextStyle(
                color: StagePalette.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_demo) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: _endDemo,
                style: TextButton.styleFrom(foregroundColor: StagePalette.text),
                child: const Text('Skip'),
              ),
            ],
          ],
          const Spacer(),
          if (widget.onConnectMidi != null) ...[
            TextButton.icon(
              onPressed: widget.onConnectMidi,
              style: TextButton.styleFrom(foregroundColor: StagePalette.text),
              icon: Icon(
                widget.midiLabel == null
                    ? Icons.usb_off_rounded
                    : Icons.usb_rounded,
                color: widget.midiLabel == null
                    ? StagePalette.textDim
                    : StagePalette.done,
              ),
              label: Text(widget.midiLabel ?? 'Connect MIDI'),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: pianoSynth.enabled
                ? 'Mute piano sound'
                : 'Play piano sound',
            onPressed: () =>
                setState(() => pianoSynth.enabled = !pianoSynth.enabled),
            icon: Icon(
              pianoSynth.enabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              color: StagePalette.text,
            ),
          ),
          if (_playAlong)
            IconButton(
              tooltip: pianoSynth.metronome
                  ? 'Turn metronome off'
                  : 'Turn metronome on',
              onPressed: _toggleMetronome,
              icon: MetronomeIcon(
                color: pianoSynth.metronome
                    ? StagePalette.text
                    : StagePalette.text.withValues(alpha: 0.4),
              ),
            ),
          if (widget.onToggleKeyboard != null) ...[
            IconButton(
              tooltip: widget.showKeyboard ? 'Hide keyboard' : 'Show keyboard',
              onPressed: widget.onToggleKeyboard,
              icon: Icon(
                widget.showKeyboard ? Icons.piano : Icons.piano_off,
                color: StagePalette.text,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (_paused && _playAlong)
            _tempoSelector()
          else
            SizedBox(
              width: 220,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: LinearProgressIndicator(
                        value: pillValue.clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                  if (waitPill)
                    Text(
                      '${widget.repeatDone}/${widget.repeatTotal}',
                      style: const TextStyle(
                        color: StagePalette.badge,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Tempo choice shown in the top bar while a play-along is paused.
  Widget _tempoSelector() {
    final options = <double>{0.6, 0.8, 1.0, widget.stage.tempo}.toList()
      ..sort();
    return SlideIn(
      offset: const Offset(30, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          for (final t in options) ...[
            GameButton(
              label: '${(t * 100).round()}%',
              onTap: () => widget.onTempo(t),
              tone: (t - widget.tempo).abs() < 1e-6
                  ? GameTone.gold
                  : GameTone.wood,
              fontSize: 15,
              minWidth: 0,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _frame;
    final countIn = _playAlong && _scroll.value < 0 && !_paused;
    final waitDone = !_playAlong && (f?.done ?? false);
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
          Column(
            children: [
              _topBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    _fitPage(c.maxWidth);
                    return RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: StaffPainter(
                          notes: _notes,
                          playheadBeat: _scroll,
                          pixelsPerBeat: _ppb,
                          inkColor: StagePalette.ink,
                          staffColor: StagePalette.ink,
                          playheadColor: StagePalette.playBar,
                          lineRatio: _playAlong ? _playLine : _waitAnchor,
                          showPlayLine: _playAlong,
                          staves: widget.staves,
                          bandColor: StagePalette.band,
                          beatsPerBar: _beatsPerBar,
                          dimmed: _paused || _demo,
                          waitBeamOpacity: _playAlong || waitDone
                              ? null
                              : () {
                                  if (_demo) return 1.0;
                                  final since = _hintSinceSec;
                                  if (since == null) return 0.0;
                                  return ((_nowSec - since) / 0.2).clamp(
                                    0.0,
                                    1.0,
                                  );
                                },
                          beatPulse: _playAlong
                              ? () {
                                  final b = _scroll.value;
                                  return (1 - 2 * (b - b.roundToDouble()).abs())
                                      .clamp(0.0, 1.0);
                                }
                              : null,
                          colorOf: _noteColor,
                          badgeColorOf: _badgeColor,
                          showEndCheck: waitDone,
                          currentIndex: _currentNoteIndex,
                          currentGlow: StagePalette.currentGlow,
                          bursts: _bursts,
                          burstColor: StagePalette.burst,
                          clockSec: () => _nowSec,
                          repaintAlso: _marks,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.showKeyboard)
                SizedBox(
                  // Taller on big screens: about a quarter of the height.
                  height: (MediaQuery.sizeOf(context).height * 0.24).clamp(
                    150.0,
                    260.0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = Size(c.maxWidth, c.maxHeight);
                      return Listener(
                        onPointerDown: (e) =>
                            _touchDown(e.pointer, e.localPosition, size),
                        onPointerUp: (e) => _touchUp(e.pointer),
                        onPointerCancel: (e) => _touchUp(e.pointer),
                        child: CustomPaint(
                          size: size,
                          painter: KeyboardPainter(
                            lowPitch: _low,
                            highPitch: _high,
                            pressed: _pressed,
                            pressedColor: StagePalette.done,
                            hint: _hint,
                            hintColor: StagePalette.keyTarget,
                            labelMiddleC: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          if (countIn)
            const Align(
              alignment: Alignment(0, -0.55),
              child: Text(
                'Get ready…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
