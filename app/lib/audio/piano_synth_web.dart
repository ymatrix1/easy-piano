import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'piano_synth.dart';

PianoSynth createPianoSynth() => _WebPianoSynth();

/// Sample every 3 semitones (C, Eb, Gb, A) from C2 to C7; nearest sample is
/// pitch-shifted, at most 1.5 semitones.
const _sampleNames = ['C', 'Eb', 'Gb', 'A'];
const _sampleOffsets = [0, 3, 6, 9];

class _Voice {
  _Voice(this.source, this.gain);
  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
}

class _WebPianoSynth implements PianoSynth {
  static const _prefKey = 'easy_piano.sound';

  web.AudioContext? _ctx;
  web.GainNode? _master;
  final _buffers = <int, web.AudioBuffer>{};
  final _voices = <int, _Voice>{};
  final _scheduled = <_Voice>[];
  Future<void>? _loading;

  @override
  bool get enabled {
    try {
      return web.window.localStorage.getItem(_prefKey) != 'off';
    } catch (_) {
      return true;
    }
  }

  @override
  set enabled(bool value) {
    try {
      web.window.localStorage.setItem(_prefKey, value ? 'on' : 'off');
    } catch (_) {}
    if (!value) stopAll();
  }

  static const _metronomeKey = 'easy_piano.metronome';

  @override
  bool get metronome {
    try {
      return web.window.localStorage.getItem(_metronomeKey) != 'off';
    } catch (_) {
      return true;
    }
  }

  @override
  set metronome(bool value) {
    try {
      web.window.localStorage.setItem(_metronomeKey, value ? 'on' : 'off');
    } catch (_) {}
  }

  web.AudioContext _context() {
    final ctx = _ctx ??= web.AudioContext(
      web.AudioContextOptions(latencyHint: 'interactive'.toJS),
    );
    _master ??= ctx.createGain()
      ..gain.value = 0.8
      ..connect(ctx.destination);
    // Browsers keep audio suspended until a user gesture; key presses count.
    if (ctx.state == 'suspended') ctx.resume();
    return ctx;
  }

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final ctx = _context();
    for (var octave = 2; octave <= 7; octave++) {
      for (var k = 0; k < _sampleNames.length; k++) {
        if (octave == 7 && k > 0) break;
        final pitch = (octave + 1) * 12 + _sampleOffsets[k];
        try {
          final data = await rootBundle.load(
            'assets/piano/${_sampleNames[k]}$octave.mp3',
          );
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final copy = Uint8List.fromList(
            bytes,
          ); // decodeAudioData detaches the buffer
          _buffers[pitch] = await ctx.decodeAudioData(copy.buffer.toJS).toDart;
        } catch (_) {
          // A missing sample just leaves a gap; neighbours cover it.
        }
      }
    }
  }

  int? _nearest(int pitch) {
    int? best;
    for (final s in _buffers.keys) {
      if (best == null || (s - pitch).abs() < (best - pitch).abs()) best = s;
    }
    return best;
  }

  _Voice? _start(int pitch, double when, int velocity) {
    final ctx = _context();
    final sample = _nearest(pitch);
    if (sample == null) return null;
    final src = ctx.createBufferSource()
      ..buffer = _buffers[sample]
      ..playbackRate.value = math.pow(2, (pitch - sample) / 12).toDouble();
    final gain = ctx.createGain();
    final level = (velocity.clamp(1, 127) / 127) * 0.9;
    gain.gain.setValueAtTime(level, when);
    src.connect(gain);
    gain.connect(_master!);
    src.start(when);
    return _Voice(src, gain);
  }

  void _release(_Voice v, double when) {
    v.gain.gain.setTargetAtTime(0, when, 0.08);
    v.source.stop(when + 0.5);
  }

  @override
  void noteOn(int pitch, {int velocity = 90}) {
    if (!enabled) return;
    load();
    final ctx = _context();
    final old = _voices.remove(pitch);
    if (old != null) _release(old, ctx.currentTime);
    final v = _start(pitch, ctx.currentTime, velocity);
    if (v != null) _voices[pitch] = v;
  }

  @override
  void noteOff(int pitch) {
    final v = _voices.remove(pitch);
    if (v != null) _release(v, _context().currentTime);
  }

  @override
  void schedule(
    int pitch,
    double startSec,
    double durSec, {
    int velocity = 80,
    bool force = false,
  }) {
    if (!enabled && !force) return;
    final ctx = _context();
    final at = ctx.currentTime + startSec;
    final v = _start(pitch, at, velocity);
    if (v == null) return;
    _release(v, at + durSec);
    _scheduled.add(v);
  }

  final _clicks = <web.OscillatorNode>[];

  @override
  void click(double startSec, {bool accent = false}) {
    final ctx = _context();
    final at = ctx.currentTime + startSec;
    final osc = ctx.createOscillator()
      ..type = 'square'
      ..frequency.value = accent ? 1600 : 1100;
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(accent ? 0.25 : 0.15, at + 0.002);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.05);
    osc.connect(gain);
    gain.connect(_master!);
    osc.start(at);
    osc.stop(at + 0.06);
    _clicks.add(osc);
  }

  @override
  void stopAll() {
    for (final o in _clicks) {
      try {
        o.stop();
      } catch (_) {}
    }
    _clicks.clear();
    final ctx = _ctx;
    if (ctx == null) return;
    for (final v in [..._voices.values, ..._scheduled]) {
      try {
        v.gain.gain.cancelScheduledValues(ctx.currentTime);
        v.gain.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
        v.source.stop(ctx.currentTime + 0.1);
      } catch (_) {}
    }
    _voices.clear();
    _scheduled.clear();
  }
}
