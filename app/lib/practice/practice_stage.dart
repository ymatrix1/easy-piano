import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/key_geometry.dart';
import '../ui/keyboard_painter.dart';
import '../ui/staff/staff_note.dart';
import '../ui/staff/staff_painter.dart';

/// FRB maps i64 to int on native and BigInt on web.
int _int(Object v) => v is BigInt ? v.toInt() : v as int;

/// Practice screen palette (our own; dark stage, cream notation, bright feedback).
abstract final class StagePalette {
  static const bgTop = Color(0xFF1B1830);
  static const bgBottom = Color(0xFF2A2346);
  static const ink = Color(0xFFF4EEDC);
  static const staff = Color(0xCCEDE6D3);
  static const current = Color(0xFFFFC83D);
  static const hit = Color(0xFF2ED3C6);
  static const miss = Color(0xFFFF6B6B);
  static const playLine = Color(0xFF3EE6FF);
  static const burst = Color(0xFF4FC3FF);
  static const keyHint = Color(0xFF8FF0E6);
  static const keyPressed = Color(0xFFFFC83D);
  static const textDim = Color(0xB3F4EEDC);
}

/// One playable stage (wait / play_along / one_note), graded by the Rust core.
///
/// Wait mode follows the reference behaviour: the notes stay on a still page,
/// the highlight jumps to the next note as soon as the right key is pressed,
/// and the page slides left (1 s ease) only when the next note passes 72% of
/// the width. Play-along scrolls notes toward a glowing play line.
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
  });

  final StageDef stage;
  final String songJson;
  final MidiInput midi;
  final int failedAttempts;
  final void Function(ResultView result) onFinished;

  @override
  State<PracticeStage> createState() => _PracticeStageState();
}

class _PracticeStageState extends State<PracticeStage>
    with TickerProviderStateMixin {
  static const _low = 48; // C3
  static const _high = 84; // C6
  static const _ppb = 110.0; // pixels per beat
  static const _waitAnchor = 0.14; // page start, as a fraction of the width
  static const _pageTurnAt = 0.72; // next note past this fraction → slide
  static const _playLine = 0.30;

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
  late final double _startMs; // stage time zero on the input clock
  FrameView? _frame;
  double _staffWidth = 1200;
  bool _finished = false;

  bool get _playAlong => widget.stage.type == 'play_along';

  @override
  void initState() {
    super.initState();
    final info = inspectSong(json: widget.songJson);
    _beatsPerBar = info.beatsPerBar.toDouble();
    _usPerBeat = 60e6 / (info.bpm * widget.stage.tempo);
    _session = PracticeSession.create(
      songJson: widget.songJson,
      mode: widget.stage.type,
      input: 'midi',
      hand: widget.stage.hand,
      tempo: widget.stage.tempo,
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
    _scroll.value = _initialTargets.isEmpty ? 0 : _initialTargets.first.beat;
    _pageAnim =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            final tw = _pageTween;
            if (tw != null) _scroll.value = tw.value;
          });
    // Play-along gets a one-bar count-in; wait mode starts right away.
    _startMs =
        widget.midi.now() + (_playAlong ? _beatsPerBar * _usPerBeat / 1000 : 0);
    _sub = widget.midi.events.listen(
      (e) => _onNote(e.pitch, e.on, e.timestampMs),
    );
    _ticker = createTicker((_) => _tick())..start();
  }

  int _usAt(double ms) => ((ms - _startMs) * 1000).round();
  double get _nowSec => widget.midi.now() / 1000;

  void _onNote(int pitch, bool on, double timestampMs) {
    final next = {..._pressed.value};
    on ? next.add(pitch) : next.remove(pitch);
    _pressed.value = next;
    _session.onNote(
      pitch: pitch,
      on_: on,
      tUs: PlatformInt64Util.from(_usAt(timestampMs)),
    );
  }

  /// Wait mode: slide the page when the next note would run past 72% of the width.
  void _maybeTurnPage(int cursor) {
    if (_playAlong || cursor >= _initialTargets.length) return;
    final nextBeat = _initialTargets[cursor].beat;
    final x = (nextBeat - _scroll.value) * _ppb;
    if (x > (_pageTurnAt - _waitAnchor) * _staffWidth) {
      _pageTween = Tween(begin: _scroll.value, end: nextBeat).animate(
        CurvedAnimation(parent: _pageAnim, curve: Curves.easeInOutCubic),
      );
      _pageAnim.forward(from: 0);
    }
  }

  void _tick() {
    if (_finished) return;
    final f = _session.tick(
      tUs: PlatformInt64Util.from(_usAt(widget.midi.now())),
    );
    if (_playAlong) _scroll.value = f.playheadBeat;
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
              ),
            );
          }
        }
      }
    }
    _bursts.removeWhere((b) => now - b.startSec > HitBurst.durationSec);
    if (changed) _targetStates = states;
    final cursorMoved = _frame == null || f.cursor != _frame!.cursor;
    if (cursorMoved) _maybeTurnPage(f.cursor);
    // Repaint every frame while bursts animate, or when marks change.
    if (changed || _bursts.isNotEmpty || cursorMoved) _marks.value++;
    _hint.value = f.cursor < targets.length
        ? {...targets[f.cursor].pitches}
        : {};
    final countInChanged =
        _frame != null && (f.playheadBeat < 0) != (_frame!.playheadBeat < 0);
    if (_frame == null ||
        f.hits != _frame!.hits ||
        f.misses != _frame!.misses ||
        f.wrong != _frame!.wrong ||
        countInChanged) {
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
      widget.onFinished(_session.result());
    }
  }

  Color _noteColor(int i) {
    final ti = _noteTarget[i];
    switch (_targetStates[ti]) {
      case 1:
        return StagePalette.hit;
      case 2:
        return StagePalette.miss;
      default:
        return ti == (_frame?.cursor ?? 0)
            ? StagePalette.current
            : StagePalette.ink;
    }
  }

  int? _currentNoteIndex() {
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
    _ticker.dispose();
    _pageAnim.dispose();
    _sub?.cancel();
    _scroll.dispose();
    _marks.dispose();
    _pressed.dispose();
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _frame;
    final countIn = _playAlong && (f?.playheadBeat ?? -1) < 0;
    final total = _initialTargets.isEmpty ? 1 : _initialTargets.length;
    final progress = ((f?.hits ?? 0) + (f?.misses ?? 0)) / total;
    const label = TextStyle(
      color: StagePalette.textDim,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [StagePalette.bgTop, StagePalette.bgBottom],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text(
                  _playAlong
                      ? 'PLAY ALONG · ${(widget.stage.tempo * 100).round()}%'
                      : 'PLAY AT YOUR PACE',
                  style: label,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(
                        StagePalette.hit,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${f?.hits ?? 0}',
                  style: label.copyWith(color: StagePalette.hit),
                ),
                const Text('  ·  ', style: label),
                Text(
                  '${f?.misses ?? 0}',
                  style: label.copyWith(color: StagePalette.miss),
                ),
                if ((f?.wrong ?? 0) > 0) ...[
                  const Text('  ·  ', style: label),
                  Text('wrong ${f!.wrong}', style: label),
                ],
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      _staffWidth = c.maxWidth;
                      return RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: StaffPainter(
                            notes: _notes,
                            playheadBeat: _scroll,
                            pixelsPerBeat: _ppb,
                            inkColor: StagePalette.ink,
                            staffColor: StagePalette.staff,
                            playheadColor: StagePalette.playLine,
                            lineRatio: _playAlong ? _playLine : _waitAnchor,
                            showPlayLine: _playAlong,
                            colorOf: _noteColor,
                            currentIndex: _currentNoteIndex,
                            currentGlow: StagePalette.current,
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
                if (countIn)
                  const Center(
                    child: Text(
                      'Get ready…',
                      style: TextStyle(
                        color: StagePalette.current,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 170,
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
                      pressedColor: StagePalette.keyPressed,
                      hint: _hint,
                      hintColor: StagePalette.keyHint,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
