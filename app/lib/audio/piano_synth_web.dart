import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

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
    final at = ctx.currentTime + math.max(0.0, startSec);
    final v = _start(pitch, at, velocity);
    if (v == null) return;
    _release(v, at + durSec);
    _scheduled.add(v);
  }

  final _clicks = <web.OscillatorNode>[];

  @override
  void click(double startSec, {bool accent = false}) {
    final ctx = _context();
    final at = ctx.currentTime + math.max(0.0, startSec);
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

  /// Drum and bass nodes, kept so [stopAll] can silence them.
  final _band = <web.AudioScheduledSourceNode>[];
  web.AudioBuffer? _noise;

  /// One second of white noise, shared by snare, hi-hats and crash.
  web.AudioBuffer _noiseBuffer(web.AudioContext ctx) {
    final cached = _noise;
    if (cached != null) return cached;
    final len = ctx.sampleRate.toInt();
    final buf = ctx.createBuffer(1, len, ctx.sampleRate);
    final data = Float32List(len);
    final rnd = math.Random(7);
    for (var i = 0; i < len; i++) {
      data[i] = rnd.nextDouble() * 2 - 1;
    }
    buf.copyToChannel(data.toJS, 0);
    return _noise = buf;
  }

  /// Filtered noise with a fast decay: snare rattle, hi-hats, crash.
  void _noiseHit(
    web.AudioContext ctx,
    double at,
    double level,
    double decay,
    double highpassHz,
  ) {
    final src = ctx.createBufferSource()..buffer = _noiseBuffer(ctx);
    final filter = ctx.createBiquadFilter()
      ..type = 'highpass'
      ..frequency.value = highpassHz;
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(level, at);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + decay);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(_master!);
    src.start(at);
    src.stop(at + decay + 0.02);
    _band.add(src);
  }

  /// A sine or triangle blip with an exponential decay.
  void _toneHit(
    web.AudioContext ctx,
    double at,
    String type,
    double fromHz,
    double toHz,
    double level,
    double decay,
  ) {
    final osc = ctx.createOscillator()..type = type;
    osc.frequency.setValueAtTime(fromHz, at);
    osc.frequency.exponentialRampToValueAtTime(toHz, at + decay * 0.35);
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(level, at);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + decay);
    osc.connect(gain);
    gain.connect(_master!);
    osc.start(at);
    osc.stop(at + decay + 0.02);
    _band.add(osc);
  }

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) {
    final ctx = _context();
    final at = ctx.currentTime + math.max(0.0, startSec);
    final v = velocity.clamp(1, 127) / 127;
    switch (gmPitch) {
      case 36: // kick: sine sweeping down from 150 Hz
        _toneHit(ctx, at, 'sine', 150, 45, 0.9 * v, 0.35);
      case 38: // snare: noise rattle plus a short body tone
        _noiseHit(ctx, at, 0.45 * v, 0.18, 1200);
        _toneHit(ctx, at, 'triangle', 200, 170, 0.35 * v, 0.1);
      case 42: // closed hi-hat
        _noiseHit(ctx, at, 0.18 * v, 0.05, 7000);
      case 46: // open hi-hat
        _noiseHit(ctx, at, 0.18 * v, 0.3, 7000);
      case 49: // crash
        _noiseHit(ctx, at, 0.22 * v, 1.2, 5000);
    }
  }

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) {
    final ctx = _context();
    final at = ctx.currentTime + math.max(0.0, startSec);
    final freq = 440 * math.pow(2, (pitch - 69) / 12).toDouble();
    final level = velocity.clamp(1, 127) / 127 * 0.5;
    // A sawtooth through a closing low-pass reads as a plucked electric bass;
    // the sine keeps the fundamental on small speakers.
    final saw = ctx.createOscillator()
      ..type = 'sawtooth'
      ..frequency.value = freq;
    final sine = ctx.createOscillator()
      ..type = 'sine'
      ..frequency.value = freq;
    final filter = ctx.createBiquadFilter()..type = 'lowpass';
    filter.frequency.setValueAtTime(freq * 8, at);
    filter.frequency.exponentialRampToValueAtTime(freq * 2, at + 0.25);
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(level, at + 0.01);
    gain.gain.setTargetAtTime(level * 0.6, at + 0.01, 0.2);
    final end = at + math.max(0.05, durSec);
    gain.gain.setTargetAtTime(0, end, 0.04);
    saw.connect(filter);
    sine.connect(filter);
    filter.connect(gain);
    gain.connect(_master!);
    for (final o in [saw, sine]) {
      o.start(at);
      o.stop(end + 0.3);
      _band.add(o);
    }
  }

  @override
  void stopAll() {
    for (final n in _band) {
      try {
        n.stop();
      } catch (_) {}
    }
    _band.clear();
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
