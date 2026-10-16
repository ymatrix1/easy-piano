import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show PlatformInt64Util;

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/key_geometry.dart';
import '../ui/keyboard_painter.dart';
import '../ui/staff/staff_note.dart';
import '../ui/staff/staff_painter.dart';

/// FRB maps i64 to int on native and BigInt on web.
int _int(Object v) => v is BigInt ? v.toInt() : v as int;

/// One playable stage (wait / play_along / one_note), graded by the Rust core.
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
    with SingleTickerProviderStateMixin {
  static const _low = 48; // C3
  static const _high = 84; // C6

  late final PracticeSession _session;
  late final List<StaffNote> _notes;
  late final List<int> _noteTarget; // staff note index → target index
  late final double _beatsPerBar;
  late final double _usPerBeat;
  final _beat = ValueNotifier<double>(0);
  final _marks = ValueNotifier<int>(0);
  final _pressed = ValueNotifier<Set<int>>({});
  final _hint = ValueNotifier<Set<int>>({});
  final _pointerPitch = <int, int>{};
  List<int> _targetStates = const [];
  late final Ticker _ticker;
  StreamSubscription<NoteEvent>? _sub;
  late final double _startMs; // stage time zero on the input clock
  FrameView? _frame;
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
    final targets = _session.targets();
    _notes = [];
    _noteTarget = [];
    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      for (var k = 0; k < t.pitches.length; k++) {
        final p = t.pitches[k];
        final f = k < t.fingers.length && t.fingers[k] > 0
            ? t.fingers[k]
            : null;
        _notes.add(StaffNote(p, t.beat, t.beats, leftHand: p < 60, finger: f));
        _noteTarget.add(i);
      }
    }
    _targetStates = [for (final t in targets) t.state];
    // Play-along gets a one-bar count-in; wait mode starts right away.
    _startMs =
        widget.midi.now() + (_playAlong ? _beatsPerBar * _usPerBeat / 1000 : 0);
    _sub = widget.midi.events.listen(
      (e) => _onNote(e.pitch, e.on, e.timestampMs),
    );
    _ticker = createTicker((_) => _tick())..start();
  }

  int _usAt(double ms) => ((ms - _startMs) * 1000).round();

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

  void _tick() {
    if (_finished) return;
    final f = _session.tick(
      tUs: PlatformInt64Util.from(_usAt(widget.midi.now())),
    );
    _beat.value = f.playheadBeat;
    final targets = _session.targets();
    final states = [for (final t in targets) t.state];
    if (!_listEq(states, _targetStates)) {
      _targetStates = states;
      _marks.value++;
    }
    final cursor = f.cursor;
    _hint.value = cursor < targets.length ? {...targets[cursor].pitches} : {};
    if (_frame == null ||
        f.hits != _frame!.hits ||
        f.misses != _frame!.misses ||
        f.wrong != _frame!.wrong) {
      setState(() => _frame = f);
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

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Color _noteColor(int i, ColorScheme scheme) {
    final ti = _noteTarget[i];
    switch (_targetStates[ti]) {
      case 1:
        return Colors.green.shade600;
      case 2:
        return Colors.red.shade600;
      default:
        return ti == (_frame?.cursor ?? 0) ? scheme.primary : scheme.onSurface;
    }
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
    _sub?.cancel();
    _beat.dispose();
    _marks.dispose();
    _pressed.dispose();
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = _frame;
    final countIn = _playAlong && (f?.playheadBeat ?? -1) < 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Chip(
                label: Text(
                  _playAlong
                      ? 'Play along · ${(widget.stage.tempo * 100).round()}%'
                      : 'Wait mode',
                ),
              ),
              const SizedBox(width: 12),
              if (countIn)
                const Text(
                  'Get ready…',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              const Spacer(),
              Text(
                '✓ ${f?.hits ?? 0}   ✗ ${f?.misses ?? 0}   wrong ${f?.wrong ?? 0}',
              ),
            ],
          ),
        ),
        Expanded(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: StaffPainter(
                notes: _notes,
                playheadBeat: _beat,
                inkColor: scheme.onSurface,
                playheadColor: scheme.primary,
                colorOf: (i) => _noteColor(i, scheme),
                repaintAlso: _marks,
              ),
            ),
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
                    pressedColor: scheme.primary,
                    hint: _hint,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
