import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;

import '../l10n/app_localizations.dart';
import '../audio/backing.dart';
import '../audio/piano_synth.dart';
import '../content/content_repo.dart';
import '../input/mic/mic_input.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import '../ui/key_geometry.dart';
import '../ui/keyboard_painter.dart';
import '../ui/metronome_icon.dart';
import '../ui/staff/score_page_view.dart';
import '../ui/staff/song_marks_parser.dart';
import '../ui/staff/song_rest_parser.dart';
import '../ui/staff/staff_note.dart';
import '../ui/staff/staff_painter.dart';
import 'generated/song_feed.dart';
import 'play_feedback.dart';

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

/// A grand staff with nothing to show on one of its staves collapses to the
/// other (e.g. a right-hand stage of a two-hand piece hides the bass staff).
Staves fitStaves(Staves staves, Iterable<StaffNote> notes) {
  if (staves != Staves.grand || notes.isEmpty) return staves;
  final playableNotes = notes.where((n) => !n.isRest && !n.isSpacer);
  final refNotes = playableNotes.isNotEmpty ? playableNotes : notes;
  if (!refNotes.any((n) => n.leftHand)) return Staves.treble;
  if (!refNotes.any((n) => !n.leftHand)) return Staves.bass;
  return staves;
}

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
    this.micMode = false,
    this.onMic,
    required this.failedAttempts,
    required this.onFinished,
    required this.staves,
    required this.tempo,
    required this.onTempo,
    required this.onRestart,
    required this.onExit,
    this.instruction,
    this.repeatDone = 0,
    this.repeatTotal = 1,
    this.showKeyboard = true,
    this.onToggleKeyboard,
    this.midiLabel,
    this.onConnectMidi,
    this.feed,
  });

  final StageDef stage;
  final String songJson;
  final MidiInput midi;

  /// Notes come from the microphone: core uses its mic timing window, and
  /// the app's own piano and backing stay silent so the mic only hears the
  /// student (docs/specs/input.md).
  final bool micMode;
  final VoidCallback? onMic;
  final int failedAttempts;
  final void Function(ResultView result) onFinished;
  final Staves staves;

  /// Effective tempo factor (stage tempo or the one picked in the pause menu).
  final double tempo;
  final void Function(double tempo) onTempo;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  /// Banner text; defaults to the localized "Play the following notes".
  final String? instruction;
  final int repeatDone;
  final int repeatTotal;

  /// The on-screen keyboard is optional (MIDI players may hide it).
  final bool showKeyboard;
  final VoidCallback? onToggleKeyboard;

  /// Connected MIDI device name, or null when none; tapping connects.
  final String? midiLabel;
  final VoidCallback? onConnectMidi;

  /// Streaming practice: the song grows while it plays; [songJson] is its
  /// first part. The stage ends only after the feed ends.
  final SongFeed? feed;

  @override
  State<PracticeStage> createState() => _PracticeStageState();
}

class _PracticeStageState extends State<PracticeStage>
    with TickerProviderStateMixin {
  /// Widest keyboard: C2–C6, middle C in the centre.
  static const _fullLow = 36, _fullHigh = 84;

  /// White keys narrower than this are hard to read and tap.
  static const _minWhiteKeyPx = 30.0;

  /// Visible key range for the keyboard width: as many octaves as fit, centred
  /// on the exercise's notes (middle C when they fit around it), whole octaves
  /// from C to C.
  int _low = _fullLow, _high = _fullHigh;
  double _keyboardWidth = 0;

  void _fitKeyboard(double width) {
    if (width == _keyboardWidth) return;
    _keyboardWidth = width;
    final octaves = ((width / _minWhiteKeyPx - 1) / 7).floor().clamp(1, 4);
    final pitches = [for (final t in _initialTargets) ...t.pitches];
    final lo = pitches.isEmpty ? 60 : pitches.reduce(math.min);
    final hi = pitches.isEmpty ? 60 : pitches.reduce(math.max);
    final centre = (lo + hi) / 2;
    // Lowest C such that the range [c, c + 12*octaves] is centred on the notes.
    var c = (((centre - 6.0 * octaves) / 12).round() * 12).clamp(
      _fullLow,
      _fullHigh - 12 * octaves,
    );
    if (lo < c) c = math.max(_fullLow, (lo ~/ 12) * 12);
    if (hi > c + 12 * octaves) {
      c = math.min(
        _fullHigh - 12 * octaves,
        ((hi + 11) ~/ 12) * 12 - 12 * octaves,
      );
    }
    _low = c;
    _high = math.min(_fullHigh, c + 12 * octaves);
  }

  static const _maxPpb = 120.0; // pixels per beat
  static const _minPpb = 70.0;
  static const _pageTurnAt =
      0.60; // next note past this fraction → slide (reference)

  /// Play bar well right of the clefs, as in the reference (rhythm line 480
  /// design px after the clef on a 1080 px tall layout ≈ 0.28 of the
  /// width); passed notes ghost under the cover in the gap.
  static const _playLineBase = 0.28;

  /// Wait-mode page start sits a little left of the play bar (reference:
  /// static notes 60 design px before the rhythm line).
  static const _waitAnchorGap = 0.03;

  /// Never start notes under the clef: on narrow screens a fraction of the
  /// width is less than the clef's own width. The extra 48 px keeps a clear
  /// gap between clef and play bar on phones.
  static const _clefClearPx = 96.0;
  double get _playLine =>
      math.max(_playLineBase, (_clefClearPx + 48) / _staffWidth);
  double get _waitAnchor =>
      math.max(_playLine - _waitAnchorGap, (_clefClearPx + 24) / _staffWidth);

  late final PracticeSession _session;
  late final List<StaffNote> _notes;
  late final List<int> _noteTarget; // staff note index → target index
  late final List<int>
  _targetFirstNote; // target index → first staff note index
  int _parsedRestBars = 0;
  // Dynamics and hairpins from the song's directives, redrawn with the staff.
  SongMarks _songMarks = SongMarks.empty;
  late final double _beatsPerBar;
  late double _usPerBeat; // changes when training slows a section down
  late final double _bpm;
  late double _tempo; // tempo of the current run

  /// Training: song beat where the current run starts (count-in ends here).
  double _leadEndBeat = 0;

  /// Training banner (slow practice intro, try again, full speed).
  SectionEventView? _sectionEvent;
  double _sectionEventSec = 0;
  late List<TargetView> _initialTargets;
  final _scroll = ValueNotifier<double>(0);
  final _marks = ValueNotifier<int>(0);
  final _pressed = ValueNotifier<Set<int>>({});
  final _hint = ValueNotifier<Set<int>>({});
  final _pointerPitch = <int, int>{};
  final _bursts = <HitBurst>[];
  final _feedback = <FeedbackMark>[]; // play-along error animations
  List<int> _targetStates = const [];
  int _keyFifths = 0;
  late final Ticker _ticker;
  late final double _introStartSec; // notes rise in (reference intro)
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
  List<BackingNote> _backing = const [];

  /// Pre-listen: the app plays the passage first; input is ignored meanwhile.
  bool _demo = false;
  double _demoStartMs = 0;
  int _demoIndex = 0;

  bool get _playAlong => widget.stage.type == 'play_along';
  bool get _paused => _pausedAtMs != null;

  @override
  void initState() {
    super.initState();
    final songRaw = widget.feed?.json ?? widget.songJson;
    try {
      final decoded = jsonDecode(songRaw);
      if (decoded is Map<String, dynamic>) {
        _keyFifths = KeySignatureLayout.parseKey(decoded['key'] as String?);
      }
    } catch (_) {
      _keyFifths = 0;
    }
    final info = inspectSong(json: widget.songJson);
    _beatsPerBar = info.beatsPerBar.toDouble();
    _bpm = info.bpm;
    _tempo = widget.tempo;
    _usPerBeat = 60e6 / (info.bpm * widget.tempo);
    _session = PracticeSession.create(
      songJson: widget.songJson,
      mode: widget.stage.type,
      input: widget.micMode ? 'mic' : 'midi',
      hand: widget.stage.hand,
      tempo: widget.tempo,
      passRatio: widget.stage.pass,
      failedAttempts: widget.failedAttempts,
      training: true,
    );
    _notes = [];
    _noteTarget = [];
    _targetFirstNote = [];
    _initialTargets = const [];
    _addTargets(_session.targets());
    widget.feed?.addListener(_onFeed);
    _scroll.value = _playAlong ? -_countInBeats : 0;
    _pageAnim =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 350),
          )
          ..addListener(() {
            final tw = _pageTween;
            if (tw != null) _scroll.value = tw.value;
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              final cur = _currentNoteIndex();
              if (!_playAlong && cur != null) {
                final targetIdx = cur < _noteTarget.length
                    ? _noteTarget[cur]
                    : -1;
                if (targetIdx >= 0) _maybeTurnPage(targetIdx);
              }
            }
          });
    if (_playAlong) {
      _backing = _companionNotes();
      pianoSynth.loadParts({for (final n in _backing) n.part});
    }
    pianoSynth.debugRegisterMixProbe((synth, leadSec) {
      final notes = _playAlong ? _backing : _companionNotes();
      scheduleBacking(
        synth,
        notes,
        fromBeat: 0,
        msPerBeat: _msPerBeat,
        beatsPerBar: _beatsPerBar.round(),
        inSec: (b) => leadSec + b * _msPerBeat / 1000,
      );
    }, _totalBeats * _msPerBeat / 1000 + 4);
    pianoSynth.load();
    if (widget.stage.preListen && widget.failedAttempts == 0) {
      _startDemo();
    } else {
      _begin();
    }
    _sub = widget.midi.events.listen(
      (e) => _onNote(e.pitch, e.on, e.timestampMs, e.velocity),
    );
    _ticker = createTicker((_) => _tick())..start();
    _introStartSec = _nowSec;
  }

  /// Adds staff notes for targets past the ones already drawn, interleaved with rests.
  void _addTargets(List<TargetView> all) {
    final songJson = widget.feed?.json ?? widget.songJson;
    _songMarks = SongMarksParser.parse(songJson);
    final totalBars = _barCount(songJson);
    final rawRests = SongRestParser.parseRests(
      songJson,
      startBar: _parsedRestBars,
      endBar: totalBars,
    );
    _parsedRestBars = totalBars;

    final Iterable<SongRest> rests;
    if (widget.staves == Staves.treble || widget.stage.hand == 'RH') {
      rests = rawRests.where((r) => !r.leftHand);
    } else if (widget.staves == Staves.bass || widget.stage.hand == 'LH') {
      rests = rawRests.where((r) => r.leftHand);
    } else {
      rests = rawRests;
    }

    final pending = <({double beat, StaffNote note, int targetIdx})>[];

    for (var i = _initialTargets.length; i < all.length; i++) {
      final t = all[i];
      for (var k = 0; k < t.pitches.length; k++) {
        final p = t.pitches[k];
        final f = k < t.fingers.length && t.fingers[k] > 0
            ? t.fingers[k]
            : null;
        final down = k < t.stemDowns.length && t.stemDowns[k];
        final two = k < t.twoStems.length && t.twoStems[k];
        final isLh = k < t.leftHands.length ? t.leftHands[k] : (p < 60);
        final dur = k < t.noteBeats.length ? t.noteBeats[k] : t.beats;
        final hasTie = k < t.ties.length && t.ties[k];
        pending.add((
          beat: t.beat,
          note: StaffNote(
            p,
            t.beat,
            dur,
            leftHand: isLh,
            stemDown: down ? true : null,
            twoStems: two,
            finger: f,
            tie: hasTie,
          ),
          targetIdx: i,
        ));
      }
    }

    for (final r in rests) {
      pending.add((
        beat: r.beat,
        note: StaffNote(
          r.leftHand ? 48 : 72,
          r.beat,
          r.beats,
          leftHand: r.leftHand,
          voice: r.voice,
          isRest: true,
        ),
        targetIdx: -1,
      ));
    }

    pending.sort((a, b) => a.beat.compareTo(b.beat));

    var lastTarget = -1;
    for (final item in pending) {
      final tIdx = item.targetIdx;
      if (tIdx >= 0) {
        if (tIdx != lastTarget) {
          while (_targetFirstNote.length <= tIdx) {
            _targetFirstNote.add(_notes.length);
          }
          lastTarget = tIdx;
        }
        _noteTarget.add(tIdx);
      } else {
        _noteTarget.add(-1);
      }
      _notes.add(item.note);
    }
    while (_targetFirstNote.length < all.length) {
      _targetFirstNote.add(_notes.length);
    }

    final old = _initialTargets.length;
    _targetStates = [..._targetStates, for (final t in all.skip(old)) t.state];
    _initialTargets = all;
  }

  /// Streaming: new bars arrived. Extends the session and, in play-along,
  /// schedules the new bars' backing and metronome clicks.
  void _onFeed() {
    if (!mounted || _finished) return;
    // Song time where the new bars start: everything before it is scheduled.
    final before = _scheduledBars * _beatsPerBar;
    try {
      _session.extend(songJson: widget.feed!.json);
      final decoded = jsonDecode(widget.feed!.json);
      if (decoded is Map<String, dynamic> && decoded['key'] != null) {
        _keyFifths = KeySignatureLayout.parseKey(decoded['key'] as String?);
      }
    } catch (_) {
      return; // a bad push never stops the stage; the next one may fit
    }
    _addTargets(_session.targets());
    _scheduledBars = _barCount(widget.feed!.json);
    if (_playAlong) {
      // New bars may bring backing parts (endless practice accompaniment).
      _backing = _companionNotes();
      if (!_paused && !_demo) {
        pianoSynth.loadParts({for (final n in _backing) n.part}).then((_) {
          if (mounted && !_finished && !_paused) _scheduleBacking(before);
        });
      }
    }
    _marks.value++;
    setState(() {});
  }

  /// Streaming: bars of the song whose backing is already scheduled.
  late int _scheduledBars = _barCount(widget.songJson);

  static int _barCount(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        final bars = decoded['bars'];
        if (bars is List) return bars.length;
      }
    } catch (_) {}
    return 0;
  }

  bool get _streaming => widget.feed != null && !widget.feed!.ended;

  List<BackingNote> _companionNotes() => [
    for (final n in companion(
      songJson: widget.feed?.json ?? widget.songJson,
      hand: widget.stage.hand,
    ))
      BackingNote(n.pitch, n.beat, n.beats, n.partName),
  ];

  double get _totalBeats {
    final songEnd = _scheduledBars * _beatsPerBar;
    final targetEnd = _initialTargets.isEmpty
        ? 1.0
        : _initialTargets.last.beat + _initialTargets.last.beats;
    return math.max(songEnd, targetEnd);
  }

  bool get _hasSubdivisions =>
      _notes.any((n) => !n.isSpacer && !n.isRest && n.beats < 1.0);

  /// Wait mode fits 3-4 measures on screen maintaining readable horizontal
  /// density without squashing long pieces across a single view.
  void _fitPage(double width) {
    _staffWidth = width;
    if (_playAlong || widget.feed != null) return;
    final usable = (0.92 - _waitAnchor) * width;
    final minPpb = _hasSubdivisions ? 95.0 : _minPpb;
    // Limit target measures to at most 4 bars per screen for spacious engraving
    final targetBeats = math.min(_totalBeats, _beatsPerBar * 4.0);
    _ppb = (usable / targetBeats).clamp(minPpb, _maxPpb);
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
    if (!_playAlong) return;
    // Notes scheduled before the samples decode are silent, so wait for
    // them; the count-in (>= 2.5 s) usually covers the first load.
    pianoSynth.loadParts({for (final n in _backing) n.part}).then((_) {
      if (!mounted || _finished || _paused) return;
      final nowBeat = (widget.midi.now() - _startMs) / _msPerBeat;
      _scheduleBacking(math.max(-_countInBeats, nowBeat));
    });
  }

  /// Schedules count-in clicks, the companion notes and, when the metronome
  /// is on, a click on every beat. [fromBeat] is song time in beats.
  void _scheduleBacking(double fromBeat) {
    final now = widget.midi.now();
    double inSec(double beat) => (_startMs + beat * _msPerBeat - now) / 1000;
    for (var b = fromBeat.ceilToDouble(); b < _leadEndBeat; b++) {
      pianoSynth.click(
        inSec(b),
        accent: (b - _leadEndBeat) % _beatsPerBar == 0,
      );
    }
    // Mic: count-in only; clicks and backing would reach the microphone.
    if (widget.micMode) return;
    if (pianoSynth.metronome) {
      for (
        var b = math.max(0.0, fromBeat.ceilToDouble());
        b < _totalBeats;
        b++
      ) {
        pianoSynth.click(inSec(b), accent: b % _beatsPerBar == 0);
      }
    }
    scheduleBacking(
      pianoSynth,
      _backing,
      fromBeat: fromBeat,
      msPerBeat: _msPerBeat,
      beatsPerBar: _beatsPerBar.round(),
      inSec: inSec,
    );
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
    _scheduleDemo(fromBeat: 0);
    _startMs = widget.midi.now();
  }

  /// Pre-listen notes use the same voice as the learner's key presses
  /// (velocity 90, live bus, no band glue or limiter), so it is one piano.
  void _scheduleDemo({required double fromBeat}) {
    final now = widget.midi.now();
    for (final t in _initialTargets) {
      if (t.beat + t.beats <= fromBeat) continue;
      final startSec = (_demoStartMs + t.beat * _msPerBeat - now) / 1000;
      final durSec = t.beats * _msPerBeat / 1000 * 0.95;
      if (startSec < 0) {
        final remaining = durSec + startSec;
        if (remaining > 0.05) {
          for (final p in t.pitches) {
            _schedulePianoKey(p, 0.01, remaining);
          }
        }
      } else {
        for (final p in t.pitches) {
          _schedulePianoKey(p, startSec, durSec);
        }
      }
    }
  }

  void _schedulePianoKey(int pitch, double startSec, double durSec) =>
      pianoSynth.schedule(
        pitch,
        startSec,
        durSec,
        velocity: 90,
        force: true,
        part: 'live',
      );

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

  /// [velocity] is the MIDI note-on velocity, or 0 when the input has none
  /// (touch, microphone). Only MIDI velocity is graded.
  void _onNote(int pitch, bool on, double timestampMs, int velocity) {
    if (!widget.micMode) {
      on ? pianoSynth.noteOn(pitch) : pianoSynth.noteOff(pitch);
    }
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
      velocity: velocity,
      tUs: PlatformInt64Util.from(_usAt(timestampMs)),
    );
  }

  void _pause() {
    pianoSynth.stopAll();
    setState(() => _pausedAtMs = widget.midi.now());
  }

  void _resume() => setState(() {
    final pausedDuration = widget.midi.now() - _pausedAtMs!;
    // Shift stage time so the song continues where it was paused.
    _startMs += pausedDuration;
    if (_demo) {
      _demoStartMs += pausedDuration;
      final currentBeat = (widget.midi.now() - _demoStartMs) / _msPerBeat;
      _scheduleDemo(fromBeat: currentBeat);
    }
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
      // Slide so the next note returns to the wait anchor, keeping notes clearly
      // visible and preventing the active target from running off the right edge.
      final end = math.min(nextBeat, _totalBeats);
      if (end <= _scroll.value + 0.01) return;
      _pageTween = Tween(begin: _scroll.value, end: end).animate(
        CurvedAnimation(parent: _pageAnim, curve: Curves.easeInOutCubic),
      );
      _pageAnim.forward(from: 0);
    }
  }

  void _tick() {
    if (_nowSec - _introStartSec < 1.1 || _nowSec < _colorFadeUntil) {
      _marks.value++;
    }
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
    final section = _session.takeSectionEvent();
    if (section != null) _onSection(section);
    final targets = _session.targets();
    final states = [for (final t in targets) t.state];
    final now = _nowSec;
    if (_playAlong) {
      for (final e in _session.takeFeedback()) {
        final mark = switch (e.kind) {
          0 when e.timing < 0 => FeedbackMark(FeedbackKind.early, now),
          0 when e.timing > 0 => FeedbackMark(FeedbackKind.late, now),
          1 => FeedbackMark(FeedbackKind.wrong, now, pitches: [e.pitch]),
          2 => FeedbackMark(
            FeedbackKind.missed,
            now,
            pitches: [...targets[e.target].pitches],
          ),
          _ => null,
        };
        if (mark != null) _feedback.add(mark);
      }
      _feedback.removeWhere((m) => m.age(now) > FeedbackMark.durationSec);
    }
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
        _feedback.isNotEmpty ||
        cursorMoved ||
        now - _cursorSinceSec < 0.25 ||
        (_hintSinceSec != null && now - _hintSinceSec! < 0.25)) {
      _marks.value++;
    }
    if (f.hintActive && _hintSinceSec == null) _hintSinceSec = now;
    if (!f.hintActive) _hintSinceSec = null;
    if (widget.micMode) _updateMicExpected(targets, f.cursor);
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
    widget.feed?.onDemand?.call(_totalBeats - _scroll.value);
    final over =
        !_streaming &&
        (_playAlong
            ? _usAt(widget.midi.now()) > _int(_session.endUs())
            : f.done);
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

  /// Note colour changes (hit, miss, current) tween linearly over this long
  /// (reference: `Actions.color(c, 0.2f)` on note heads).
  static const _colorFadeSec = 0.2;
  final _colorFade = <int, (Color from, Color to, double since)>{};
  double _colorFadeUntil = 0;

  /// Training: a section was judged. On a replay, restart the clock one
  /// count-in before the section at the new tempo (reference: seek back to
  /// the section start; practice runs at 75%).
  void _onSection(SectionEventView e) {
    if (e.replay || e.practice || e.intro || !e.passed) {
      _sectionEvent = e;
      _sectionEventSec = _nowSec;
    }
    if (!e.replay) return;
    Sfx.play(
      e.intro
          ? SfxKind.open
          : e.passed
          ? SfxKind.win
          : SfxKind.lose,
    );
    pianoSynth.stopAll();
    _tempo = e.tempo;
    _usPerBeat = 60e6 / (_bpm * e.tempo);
    _leadEndBeat = e.beat;
    // Practice intro: give the banner time before the count-in starts.
    final introMs = e.intro ? 1500.0 : 0.0;
    final from = e.beat - _countInBeats;
    _startMs = widget.midi.now() + introMs - from * _msPerBeat;
    _feedback.clear();
    _bursts.clear();
    _scroll.value = from;
    if (introMs > 0) {
      Future.delayed(Duration(milliseconds: introMs.round()), () {
        if (mounted && !_finished && !_paused) _scheduleBacking(from);
      });
    } else {
      _scheduleBacking(from);
    }
  }

  /// Training banner. Practice intro (ours, timed like the reference's):
  /// a badge pops in (0.6 s) while its label fades in, holds, then everything
  /// fades out by [_introSec]. Try-again / full-speed banners are shorter.
  static const _introSec = 2.2, _bannerSec = 1.4;

  Widget _sectionBanner(SectionEventView e) {
    final l = AppLocalizations.of(context);
    final age = _nowSec - _sectionEventSec;
    final total = e.intro ? _introSec : _bannerSec;
    if (age > total) return const SizedBox.shrink();
    final pop = Curves.elasticOut.transform((age / 0.6).clamp(0.0, 1.0));
    final fadeIn = ((age - 0.2) / 0.3).clamp(0.0, 1.0);
    final fadeOut = ((total - age) / 0.3).clamp(0.0, 1.0);
    final (icon, text, color) = e.intro || e.practice
        ? (
            Icons.slow_motion_video_rounded,
            e.intro ? l.slowPracticeIntro : l.slowPractice,
            StagePalette.current,
          )
        : e.passed
        ? (Icons.speed_rounded, l.sectionFullSpeed, StagePalette.done)
        : (Icons.replay_rounded, l.sectionTryAgain, StagePalette.miss);
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: Opacity(
          opacity: fadeOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.2 + 0.8 * pop,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(blurRadius: 18, color: Colors.black26),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 52),
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: fadeIn,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e.practice ? '$text · ${(e.tempo * 100).round()}%' : text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _noteColor(int i) {
    final to = _targetNoteColor(i);
    final now = _nowSec;
    final f = _colorFade[i];
    if (f == null) {
      _colorFade[i] = (to, to, -1e9);
      return to;
    }
    final (from, prevTo, since) = f;
    if (to != prevTo) {
      _colorFade[i] = (_lerpFade(from, prevTo, since, now), to, now);
      _colorFadeUntil = now + _colorFadeSec;
      return _colorFade[i]!.$1;
    }
    return _lerpFade(from, to, since, now);
  }

  static Color _lerpFade(Color from, Color to, double since, double now) {
    final t = ((now - since) / _colorFadeSec).clamp(0.0, 1.0);
    return Color.lerp(from, to, t)!;
  }

  Color _targetNoteColor(int i) {
    final ti = _noteTarget[i];
    if (ti < 0 || ti >= _targetStates.length) {
      return StagePalette.ink;
    }
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
    final ti = _noteTarget[i];
    if (ti < 0) return null;
    return ti == _activeIndex ? StagePalette.badgeCurrent : null;
  }

  /// Target highlighted now: the demo position during pre-listen, else the cursor.
  /// Tells the mic which notes the lesson expects now (score-informed
  /// detection, docs/specs/input.md): in wait mode the target at the cursor
  /// and the next one; in play-along the pending targets from half a beat
  /// back to 0.6 s ahead.
  void _updateMicExpected(List<TargetView> targets, int cursor) {
    final want = <int>{};
    if (_playAlong) {
      final beat = _scroll.value;
      final ahead = 600 / _msPerBeat;
      for (final t in targets) {
        if (t.state == 0 && t.beat >= beat - 0.5 && t.beat <= beat + ahead) {
          want.addAll(t.pitches);
        }
      }
    } else {
      for (var i = cursor; i < targets.length && i <= cursor + 1; i++) {
        want.addAll(targets[i].pitches);
      }
    }
    if (!setEquals(want, micInput.expected)) micInput.expected = want;
  }

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
    _onNote(pitch, true, widget.midi.now(), 0);
  }

  void _touchUp(int pointer) {
    final pitch = _pointerPitch.remove(pointer);
    if (pitch != null) _onNote(pitch, false, widget.midi.now(), 0);
  }

  @override
  void dispose() {
    if (widget.micMode) micInput.expected = const {};
    pianoSynth.stopAll();
    widget.feed?.removeListener(_onFeed);
    _ticker.dispose();
    _pageAnim.dispose();
    _sub?.cancel();
    _scroll.dispose();
    _marks.dispose();
    _pressed.dispose();
    _hint.dispose();
    super.dispose();
  }

  /// Progress pill: song position (play-along), repeats done, or notes judged.
  Widget _progressPill(double value, bool showCount) => SizedBox(
    width: 220,
    height: 22,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ),
        if (showCount)
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
  );

  /// Endless practice has no end to measure against: count hit notes and
  /// the current streak instead of a progress bar.
  Widget _pill(double value, bool showCount) {
    if (widget.feed == null) return _progressPill(value, showCount);
    final f = _frame;
    Widget stat(IconData icon, int n) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: StagePalette.text),
        const SizedBox(width: 4),
        Text(
          '$n',
          style: const TextStyle(
            color: StagePalette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stat(Icons.music_note_rounded, f?.hits ?? 0),
          const SizedBox(width: 14),
          stat(Icons.local_fire_department_rounded, f?.streak ?? 0),
        ],
      ),
    );
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
    return LayoutBuilder(
      builder: (context, box) {
        // Phones: MIDI shows as an icon and the progress bar drops to its own
        // full-width row, so nothing overflows off the right edge.
        final narrow = box.maxWidth < 720;
        final progress = _paused && _playAlong
            ? _tempoSelector()
            : _pill(pillValue, waitPill);
        final row = Row(
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
                  tooltip: AppLocalizations.of(context).resume,
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
                  tooltip: AppLocalizations.of(context).restart,
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
                  tooltip: AppLocalizations.of(context).exitToMap,
                ),
              ),
            ] else ...[
              GameRoundButton(
                icon: Icons.pause_rounded,
                onTap: _pause,
                tone: GameTone.gold,
                size: 46,
                tooltip: AppLocalizations.of(context).pause,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _demo
                      ? AppLocalizations.of(context).listenFirst
                      : _playAlong
                      ? AppLocalizations.of(context)
                            .playAlongTempo((_tempo * 100).round())
                      : widget.instruction ??
                            AppLocalizations.of(context).playFollowingNotes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: StagePalette.text,
                    fontSize: narrow ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_demo) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _endDemo,
                  style: TextButton.styleFrom(
                    foregroundColor: StagePalette.text,
                  ),
                  child: Text(AppLocalizations.of(context).skip),
                ),
              ],
            ],
            if (_paused) const Spacer() else const SizedBox(width: 8),
            if (widget.onMic != null)
              IconButton(
                onPressed: widget.onMic,
                tooltip: widget.micMode
                    ? AppLocalizations.of(context).micListening
                    : AppLocalizations.of(context).micInput,
                icon: Icon(
                  widget.micMode ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: widget.micMode
                      ? StagePalette.done
                      : StagePalette.textDim,
                ),
              ),
            if (widget.onConnectMidi != null && narrow)
              IconButton(
                onPressed: widget.onConnectMidi,
                tooltip:
                    widget.midiLabel ??
                    AppLocalizations.of(context).connectMidi,
                icon: Icon(
                  widget.midiLabel == null
                      ? Icons.usb_off_rounded
                      : Icons.usb_rounded,
                  color: widget.midiLabel == null
                      ? StagePalette.textDim
                      : StagePalette.done,
                ),
              )
            else if (widget.onConnectMidi != null) ...[
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
                label: Text(
                  widget.midiLabel ?? AppLocalizations.of(context).connectMidi,
                ),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Study / Static Score View',
              onPressed: () {
                _pause();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ScorePageView(
                      notes: _notes,
                      totalBeats: _totalBeats,
                      beatsPerBar: _beatsPerBar,
                      keyFifths: _keyFifths,
                      staves: widget.staves,
                      title: widget.stage.type,
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.menu_book_rounded,
                color: StagePalette.text,
              ),
            ),
            IconButton(
              tooltip: pianoSynth.enabled
                  ? AppLocalizations.of(context).mutePianoSound
                  : AppLocalizations.of(context).playPianoSound,
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
                    ? AppLocalizations.of(context).metronomeOff
                    : AppLocalizations.of(context).metronomeOn,
                onPressed: _toggleMetronome,
                icon: MetronomeIcon(
                  color: pianoSynth.metronome
                      ? StagePalette.text
                      : StagePalette.text.withValues(alpha: 0.4),
                ),
              ),
            if (widget.onToggleKeyboard != null) ...[
              IconButton(
                tooltip: widget.showKeyboard
                    ? AppLocalizations.of(context).hideKeyboard
                    : AppLocalizations.of(context).showKeyboard,
                // The keyboard is hidden for the whole demo; a toggle then would do nothing.
                onPressed: _demo ? null : widget.onToggleKeyboard,
                icon: Icon(
                  widget.showKeyboard ? Icons.piano : Icons.piano_off,
                  color: StagePalette.text,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (!narrow) progress,
          ],
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 8 : 16, 10, narrow ? 8 : 20, 0),
          child: narrow
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row,
                    const SizedBox(height: 6),
                    _paused && _playAlong
                        ? progress
                        : SizedBox(
                            height: 16,
                            width: double.infinity,
                            child: _pill(pillValue, waitPill),
                          ),
                  ],
                )
              : row,
        );
      },
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
                        foregroundPainter: _playAlong
                            ? StaffFeedbackPainter(
                                marks: _feedback,
                                lineX: _playLine * c.maxWidth,
                                clockSec: () => _nowSec,
                                earlyLabel: AppLocalizations.of(context).early,
                                lateLabel: AppLocalizations.of(context).late,
                                repaint: _marks,
                              )
                            : null,
                        painter: StaffPainter(
                          notes: _notes,
                          playheadBeat: _scroll,
                          pixelsPerBeat: _ppb,
                          inkColor: StagePalette.ink,
                          staffColor: StagePalette.ink,
                          playheadColor: StagePalette.playBar,
                          lineRatio: _playAlong ? _playLine : _waitAnchor,
                          showPlayLine: _playAlong,
                          // Streamed bars may add notes to either staff later.
                          staves: widget.feed == null
                              ? fitStaves(widget.staves, _notes)
                              : widget.staves,
                          bandColor: StagePalette.band,
                          beatsPerBar: _beatsPerBar,
                          keyFifths: _keyFifths,
                          dynamics: _songMarks.dynamics,
                          hairpins: _songMarks.hairpins,
                          // Streamed feeds do not know their end yet.
                          endBeat:
                              widget.feed == null && _initialTargets.isNotEmpty
                              ? _totalBeats
                              : null,
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
                          introStartSec: _introStartSec,
                          repaintAlso: _marks,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.showKeyboard && !_demo)
                SizedBox(
                  // Taller on big screens: about a quarter of the height.
                  height: (MediaQuery.sizeOf(context).height * 0.24).clamp(
                    150.0,
                    260.0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = Size(c.maxWidth, c.maxHeight);
                      _fitKeyboard(c.maxWidth);
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
                            middleCLabel: AppLocalizations.of(context)
                                .middleCLabel,
                          ),
                          foregroundPainter: _playAlong
                              ? KeyFeedbackPainter(
                                  marks: _feedback,
                                  lowPitch: _low,
                                  highPitch: _high,
                                  clockSec: () => _nowSec,
                                  repaint: _marks,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          if (_sectionEvent != null) _sectionBanner(_sectionEvent!),
          if (countIn)
            Align(
              alignment: const Alignment(0, -0.55),
              child: Text(
                AppLocalizations.of(context).getReady,
                style: const TextStyle(
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
