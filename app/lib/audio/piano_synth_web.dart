import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'piano_synth.dart';

PianoSynth createPianoSynth() => _WebPianoSynth();

/// Pitched samples every 3 semitones (C, Eb, Gb, A); the nearest one is
/// pitch-shifted, at most 1.5 semitones.
const _sampleNames = ['C', 'Eb', 'Gb', 'A'];

/// A pitched instrument: asset folder, sample range and sustain loop.
class _Instrument {
  const _Instrument(this.dir, this.lowOctave, this.highOctave, {this.loop});

  final String dir;
  final int lowOctave;
  final int highOctave;

  /// (start, end) seconds of a steady stretch to loop for long notes;
  /// null plays the sample once (it decays on its own).
  final (double, double)? loop;

  Iterable<(int, String)> get files sync* {
    for (var octave = lowOctave; octave <= highOctave; octave++) {
      for (var k = 0; k < _sampleNames.length; k++) {
        if (octave == highOctave && k > 0) break; // top sample is a C
        yield ((octave + 1) * 12 + 3 * k, '$dir/${_sampleNames[k]}$octave.mp3');
      }
    }
  }
}

/// Salamander Grand (CC-BY 3.0) and FluidR3 band instruments (MIT); see
/// `app/assets/*/README.md`.
const _instruments = {
  'piano': _Instrument('assets/piano', 1, 8),
  'bass': _Instrument('assets/band/bass', 1, 4),
  'strings': _Instrument('assets/band/strings', 3, 6, loop: (0.5, 2.9)),
  'choir': _Instrument('assets/band/choir', 3, 6, loop: (0.5, 2.9)),
};

/// Virtuosity Drums one-shots (CC0) by General MIDI percussion number.
/// Several hits per drum play in turn (round robin) so repeated notes don't
/// sound like a machine gun.
const _drumFiles = {
  36: ['kick', 'kick_2', 'kick_3'],
  38: ['snare', 'snare_2', 'snare_3'],
  42: ['hihat_closed', 'hihat_closed_2', 'hihat_closed_3'],
  46: ['hihat_open'],
  49: ['crash'],
};

/// A lighter closed hi-hat hit, used below this velocity (off-beat hats).
const _softHatFile = 'hihat_closed_soft';
const _softHatBelow = 72;

/// Instrument each score part needs, for [PianoSynth.loadParts].
const _partInstrument = {
  'BASS': 'bass',
  'PAD': 'strings',
  'CHOIR': 'choir',
  'DRUMS': 'drums',
};

class _Voice {
  _Voice(this.source, this.gain);
  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
}

class _WebPianoSynth implements PianoSynth {
  _WebPianoSynth([this._offline]);

  static const _prefKey = 'easy_piano.sound';

  /// Set for offline renders (mix measurements); null for live playback.
  final web.OfflineAudioContext? _offline;
  web.BaseAudioContext? _ctx;

  /// Mix chain: part buses -> [_glue] compressor -> [_limiter] -> [_out].
  /// Live key presses skip the dynamics (each adds a few ms of look-ahead)
  /// and go straight to [_out] through the `live` bus.
  web.GainNode? _out;
  web.DynamicsCompressorNode? _glue;
  web.ConvolverNode? _reverb;

  /// instrument -> pitch -> decoded sample.
  final _samples = <String, Map<int, web.AudioBuffer>>{};
  final _drums = <int, List<web.AudioBuffer>>{};
  final _drumTurn = <int, int>{};
  web.AudioBuffer? _softHat;
  final _loads = <String, Future<void>>{};
  final _voices = <int, _Voice>{};
  final _scheduled = <_Voice>[];

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

  web.BaseAudioContext _context() {
    final existing = _ctx;
    if (existing != null) {
      // Browsers keep audio suspended until a user gesture; key presses count.
      if (_offline == null && existing.state == 'suspended') {
        (existing as web.AudioContext).resume();
      }
      return existing;
    }
    final ctx = _ctx =
        _offline ??
        web.AudioContext(
          web.AudioContextOptions(latencyHint: 'interactive'.toJS),
        );
    // Soft clipper on the very end: no look-ahead (no latency), catches the
    // learner's loud chords that skip the limiter.
    final clip = ctx.createWaveShaper()
      ..curve = _softClipCurve()
      ..connect(ctx.destination);
    final out = _out = ctx.createGain()
      ..gain.value = 1.0
      ..connect(clip);
    // Brick-wall-ish limiter keeps peaks under about -1 dBFS.
    final limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value = 0;
    limiter.ratio.value = 20;
    limiter.attack.value = 0.001;
    limiter.release.value = 0.1;
    limiter.connect(out);
    // Gentle bus compression glues the band together.
    final glue = _glue = ctx.createDynamicsCompressor();
    glue.threshold.value = -20;
    glue.knee.value = 12;
    glue.ratio.value = 2.5;
    glue.attack.value = 0.01;
    glue.release.value = 0.25;
    glue.connect(limiter);
    // Short hall from a generated impulse response (no asset to license).
    final reverbReturn = ctx.createGain()
      ..gain.value = 1.0
      ..connect(glue);
    _reverb = ctx.createConvolver()
      ..buffer = _impulseResponse(ctx, 1.8)
      ..connect(reverbReturn);
    if (_offline == null && ctx.state == 'suspended') {
      (ctx as web.AudioContext).resume();
    }
    return ctx;
  }

  /// Linear up to 0.7, then a smooth knee that never exceeds 0.98.
  static JSFloat32Array _softClipCurve() {
    const n = 2049;
    final curve = Float32List(n);
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1) * 2 - 1;
      final a = x.abs();
      final y = a <= 0.7 ? a : 0.7 + 0.28 * _tanh((a - 0.7) / 0.28);
      curve[i] = x < 0 ? -y : y;
    }
    return curve.toJS;
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  /// Stereo decaying noise, darker as it decays: a plain room/hall tail.
  static web.AudioBuffer _impulseResponse(
    web.BaseAudioContext ctx,
    double seconds,
  ) {
    final rate = ctx.sampleRate;
    final len = (rate * seconds).toInt();
    final buf = ctx.createBuffer(2, len, rate);
    final rnd = math.Random(11);
    for (var c = 0; c < 2; c++) {
      final data = Float32List(len);
      var lp = 0.0;
      for (var i = 0; i < len; i++) {
        final t = i / rate;
        // One-pole low-pass whose cutoff falls over time.
        final a = 0.15 + 0.8 * math.exp(-t * 3);
        lp += a * ((rnd.nextDouble() * 2 - 1) - lp);
        data[i] = lp * math.exp(-t * 3.8) * (t < 0.01 ? t / 0.01 : 1);
      }
      buf.copyToChannel(data.toJS, c);
    }
    return buf;
  }

  @override
  Future<void> load() => _loadInstrument('piano');

  @override
  Future<void> loadParts(Iterable<String> parts) => Future.wait([
    load(),
    for (final p in parts)
      if (_partInstrument[p] case final inst?) _loadInstrument(inst),
  ]);

  /// Wall time of the first piano load, for mix-probe reports.
  int? _loadMs;

  Future<void> _loadInstrument(String name) =>
      _loads[name] ??= _fetchInstrument(name);

  Future<void> _fetchInstrument(String name) async {
    final watch = Stopwatch()..start();
    final ctx = _context();
    if (name == 'drums') {
      final hits = <int, List<web.AudioBuffer?>>{
        for (final MapEntry(key: gm, value: files) in _drumFiles.entries)
          gm: List.filled(files.length, null),
      };
      await Future.wait([
        for (final MapEntry(key: gm, value: files) in _drumFiles.entries)
          for (var i = 0; i < files.length; i++)
            _decode(
              ctx,
              'assets/band/drums/${files[i]}.mp3',
            ).then((b) => hits[gm]![i] = b),
        _decode(
          ctx,
          'assets/band/drums/$_softHatFile.mp3',
        ).then((b) => _softHat = b),
      ]);
      hits.forEach((gm, l) {
        final ok = l.whereType<web.AudioBuffer>().toList();
        if (ok.isNotEmpty) _drums[gm] = ok;
      });
      return;
    }
    final map = _samples.putIfAbsent(name, () => {});
    final loop = _instruments[name]!.loop;
    // All files of an instrument in parallel; decoding order doesn't matter.
    await Future.wait([
      for (final (pitch, path) in _instruments[name]!.files)
        _decode(ctx, path).then((b) {
          if (b == null) return;
          if (loop != null) _crossfadeLoop(b, loop.$1, loop.$2);
          map[pitch] = b;
        }),
    ]);
    _nearestCache.clear();
    if (name == 'piano') _loadMs ??= watch.elapsedMilliseconds;
  }

  /// Blends the end of the loop into the audio just before its start
  /// (equal-power, 150 ms), so the jump from loop end back to loop start is
  /// seamless: no click, no level dip.
  static void _crossfadeLoop(web.AudioBuffer buf, double from, double to) {
    final rate = buf.sampleRate;
    final start = (from * rate).round();
    final end = math.min((to * rate).round(), buf.length);
    final fade = math.min((0.15 * rate).round(), start);
    for (var c = 0; c < buf.numberOfChannels; c++) {
      final data = buf.getChannelData(c).toDart;
      for (var i = 0; i < fade; i++) {
        final w = i / fade * math.pi / 2;
        final tail = end - fade + i;
        data[tail] =
            data[tail] * math.cos(w) + data[start - fade + i] * math.sin(w);
      }
      buf.copyToChannel(data.toJS, c);
    }
  }

  /// Decodes one bundled MP3; a missing file leaves a gap that neighbours
  /// cover.
  Future<web.AudioBuffer?> _decode(
    web.BaseAudioContext ctx,
    String path,
  ) async {
    try {
      final data = await rootBundle.load(path);
      // decodeAudioData detaches the buffer, so hand it a copy.
      final copy = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return await ctx.decodeAudioData(copy.buffer.toJS).toDart;
    } catch (_) {
      return null;
    }
  }

  /// (instrument, pitch) -> nearest decoded sample; cleared on every load.
  final _nearestCache = <(String, int), int?>{};

  int? _nearest(String inst, int pitch) {
    final key = (inst, pitch);
    if (_nearestCache.containsKey(key)) return _nearestCache[key];
    int? best;
    for (final s in _samples[inst]?.keys ?? const <int>[]) {
      if (best == null || (s - pitch).abs() < (best - pitch).abs()) best = s;
    }
    return _nearestCache[key] = best;
  }

  /// Velocity -> gain: a gentle curve so soft notes stay audible.
  static double _velGain(int velocity) =>
      math.pow(velocity.clamp(1, 127) / 127, 1.5).toDouble();

  /// Starts [inst] at [pitch]. Piano gets a velocity-keyed low-pass (soft
  /// notes are darker, like a real hammer); looped instruments sustain.
  _Voice? _start(
    String inst,
    int pitch,
    double when,
    int velocity,
    web.AudioNode dest, {
    double attack = 0.002,
  }) {
    final ctx = _context();
    final sample = _nearest(inst, pitch);
    if (sample == null) return null;
    final spec = _instruments[inst]!;
    final src = ctx.createBufferSource()
      ..buffer = _samples[inst]![sample]
      ..playbackRate.value = math.pow(2, (pitch - sample) / 12).toDouble();
    if (spec.loop case (final from, final to)) {
      src
        ..loop = true
        ..loopStart = from
        ..loopEnd = to;
    }
    final gain = ctx.createGain();
    final level = _velGain(velocity);
    if (attack > 0.005) {
      gain.gain.setValueAtTime(0, when);
      gain.gain.linearRampToValueAtTime(level, when + attack);
    } else {
      gain.gain.setValueAtTime(level, when);
    }
    if (inst == 'piano') {
      final v = velocity.clamp(1, 127) / 127;
      final tone = ctx.createBiquadFilter()
        ..type = 'lowpass'
        ..Q.value = 0.5
        ..frequency.value = 1200 + 14000 * v * v;
      src.connect(tone);
      tone.connect(gain);
    } else {
      src.connect(gain);
    }
    gain.connect(dest);
    src.start(when);
    return _Voice(src, gain);
  }

  /// Damper-style release: [tau] is the fade time constant.
  void _release(_Voice v, double when, {double tau = 0.12}) {
    v.gain.gain.cancelScheduledValues(when);
    v.gain.gain.setTargetAtTime(0, when, tau);
    v.source.stop(when + tau * 8);
  }

  @override
  void noteOn(int pitch, {int velocity = 90}) {
    if (!enabled) return;
    load();
    final ctx = _context();
    final old = _voices.remove(pitch);
    if (old != null) _release(old, ctx.currentTime, tau: 0.05);
    final v = _start('piano', pitch, ctx.currentTime, velocity, _bus('live'));
    if (v != null) _voices[pitch] = v;
  }

  @override
  void noteOff(int pitch) {
    final v = _voices.remove(pitch);
    if (v != null) _release(v, _context().currentTime);
  }

  double _at(double startSec) => _context().currentTime + math.max(0, startSec);

  @override
  void schedule(
    int pitch,
    double startSec,
    double durSec, {
    int velocity = 80,
    bool force = false,
    String part = 'piano',
  }) {
    if (!enabled && !force) return;
    final at = _at(startSec);
    final v = _start('piano', pitch, at, velocity, _bus(part));
    if (v == null) return;
    _release(v, at + durSec);
    _scheduled.add(v);
  }

  final _clicks = <web.OscillatorNode>[];

  @override
  void click(double startSec, {bool accent = false}) {
    final ctx = _context();
    final at = _at(startSec);
    final osc = ctx.createOscillator()
      ..type = 'square'
      ..frequency.value = accent ? 1600 : 1100;
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(accent ? 0.25 : 0.15, at + 0.002);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.05);
    osc.connect(gain);
    gain.connect(_out!);
    osc.start(at);
    osc.stop(at + 0.06);
    _clicks.add(osc);
  }

  /// One gain node per part, between the voices and the mix chain.
  final _buses = <String, web.GainNode>{};

  /// Default mix, from offline measurements of Ode to Joy play-along
  /// (docs/specs/content-format.md). `live` is the learner's own keys.
  static const _defaultLevels = {
    'live': 1.0,
    'piano': 1.0,
    'ACC': 1.0,
    'DRUMS': 0.19,
    'BASS': 1.1,
    'PAD': 0.37,
    'CHOIR': 0.67,
  };

  /// Reverb send per part: pads and voices sit further back than drums.
  static const _reverbSends = {
    'live': 0.12,
    'piano': 0.14,
    'ACC': 0.16,
    'DRUMS': 0.08,
    'BASS': 0.03,
    'PAD': 0.35,
    'CHOIR': 0.40,
  };

  web.GainNode _bus(String part) {
    final existing = _buses[part];
    if (existing != null) return existing;
    final ctx = _context();
    final bus = ctx.createGain()..gain.value = _defaultLevels[part] ?? 1.0;
    bus.connect(part == 'live' ? _out! : _glue!);
    final send = ctx.createGain()..gain.value = _reverbSends[part] ?? 0.1;
    bus.connect(send);
    send.connect(_reverb!);
    return _buses[part] = bus;
  }

  @override
  void setPartLevel(String part, double level) {
    final base = _defaultLevels[part] ?? 1.0;
    _bus(part).gain.value = base * level.clamp(0.0, 2.0);
  }

  /// Band voices, kept so [stopAll] can silence them.
  final _band = <_Voice>[];

  /// Sounding open hi-hat; a closed hi-hat chokes it, like a real foot pedal.
  _Voice? _openHat;

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) {
    final hits = _drums[gmPitch];
    if (hits == null) return;
    final turn = _drumTurn[gmPitch] = (_drumTurn[gmPitch] ?? -1) + 1;
    final soft = _softHat;
    final buf = gmPitch == 42 && velocity < _softHatBelow && soft != null
        ? soft
        : hits[turn % hits.length];
    final ctx = _context();
    final at = _at(startSec);
    if (gmPitch == 42 || gmPitch == 46) {
      final open = _openHat;
      if (open != null) _release(open, at, tau: 0.02);
      _openHat = null;
    }
    final src = ctx.createBufferSource()..buffer = buf;
    final gain = ctx.createGain()..gain.value = _velGain(velocity);
    src.connect(gain);
    gain.connect(_bus('DRUMS'));
    src.start(at);
    final v = _Voice(src, gain);
    if (gmPitch == 46) _openHat = v;
    _band.add(v);
  }

  /// A sampled band note held for [durSec], then released over [tau].
  void _bandNote(
    String inst,
    String part,
    int pitch,
    double startSec,
    double durSec,
    int velocity, {
    double attack = 0.002,
    double tau = 0.06,
  }) {
    final at = _at(startSec);
    final v = _start(inst, pitch, at, velocity, _bus(part), attack: attack);
    if (v == null) return;
    _release(v, at + math.max(0.05, durSec), tau: tau);
    _band.add(v);
  }

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _bandNote('bass', 'BASS', pitch, startSec, durSec, velocity);

  @override
  void pad(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _bandNote(
        'strings',
        'PAD',
        pitch,
        startSec,
        durSec,
        velocity,
        attack: 0.12,
        tau: 0.25,
      );

  @override
  void choir(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _bandNote(
        'choir',
        'CHOIR',
        pitch,
        startSec,
        durSec,
        velocity,
        attack: 0.15,
        tau: 0.25,
      );

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
    for (final v in [..._voices.values, ..._scheduled, ..._band]) {
      try {
        v.gain.gain.cancelScheduledValues(ctx.currentTime);
        v.gain.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
        v.source.stop(ctx.currentTime + 0.1);
      } catch (_) {}
    }
    _voices.clear();
    _scheduled.clear();
    _band.clear();
    _openHat = null;
  }

  @override
  void debugRegisterMixProbe(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  ) {
    if (_offline != null || !Uri.base.queryParameters.containsKey('mixprobe')) {
      return;
    }
    globalContext.setProperty(
      'epMeasureMix'.toJS,
      (() => _measureMix(
        schedule,
        durSec,
      ).then((m) => jsonEncode(m).toJS).toJS).toJS,
    );
  }

  static const _probeParts = ['piano', 'ACC', 'DRUMS', 'BASS', 'PAD', 'CHOIR'];

  Future<Map<String, Object>> _measureMix(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  ) async {
    await loadParts(_partInstrument.keys);
    const rate = 44100;
    final out = <String, Object>{'durSec': durSec, 'loadMs': _loadMs ?? -1};
    for (final solo in [null, ..._probeParts]) {
      final off = web.OfflineAudioContext(
        web.OfflineAudioContextOptions(
          numberOfChannels: 2,
          length: (durSec * rate).ceil(),
          sampleRate: rate,
        ),
      );
      final synth = _WebPianoSynth(off).._copySamplesFrom(this);
      if (solo != null) {
        for (final p in _probeParts) {
          if (p != solo) synth.setPartLevel(p, 0);
        }
      }
      schedule(synth, 0.5);
      final buf = await off.startRendering().toDart;
      out[solo ?? 'mix'] = _levels(buf);
    }
    // Headroom of the learner's own keys (no limiter): a loud two-hand chord.
    out['liveChord'] = _levels(
      await _renderOffline(3, (synth) {
        for (final p in [36, 48, 52, 55, 60, 64, 67, 72]) {
          synth.schedule(p, 0.1, 2, velocity: 127, force: true, part: 'live');
        }
      }),
    );
    // Loop seams: a held pad note crosses the loop point twice; report the
    // loudest 10 ms window jump in dB (a click shows as a spike).
    // C4 is an exact sample, so seams fall at 0.1 + 2.9 s and every 2.4 s.
    final pad = await _renderOffline(8, (synth) => synth.pad(60, 0.1, 7));
    out['padBodyJumpDb'] = _maxJumpDb(pad, fromSec: 1, toSec: 2.9);
    out['padSeamJumpDb'] = math.max(
      _maxJumpDb(pad, fromSec: 2.95, toSec: 3.06),
      _maxJumpDb(pad, fromSec: 5.35, toSec: 5.46),
    );
    // A click is a sample step much larger than the waveform's usual steps.
    out['padBodyStep'] = _maxStep(pad, 1, 2.9);
    out['padSeamStep'] = math.max(
      _maxStep(pad, 2.99, 3.01),
      _maxStep(pad, 5.39, 5.41),
    );
    return out;
  }

  Future<web.AudioBuffer> _renderOffline(
    double seconds,
    void Function(_WebPianoSynth synth) play,
  ) {
    const rate = 44100;
    final off = web.OfflineAudioContext(
      web.OfflineAudioContextOptions(
        numberOfChannels: 2,
        length: (seconds * rate).ceil(),
        sampleRate: rate,
      ),
    );
    play(_WebPianoSynth(off).._copySamplesFrom(this));
    return off.startRendering().toDart;
  }

  /// Largest sample-to-sample step on channel 0 between two times.
  static double _maxStep(web.AudioBuffer buf, double fromSec, double toSec) {
    final data = buf.getChannelData(0).toDart;
    final from = (fromSec * buf.sampleRate).round();
    final to = math.min(data.length, (toSec * buf.sampleRate).round());
    var worst = 0.0;
    for (var i = from + 1; i < to; i++) {
      worst = math.max(worst, (data[i] - data[i - 1]).abs());
    }
    return worst;
  }

  /// Largest level change between neighbouring 10 ms windows, in dB.
  static double _maxJumpDb(
    web.AudioBuffer buf, {
    required double fromSec,
    required double toSec,
  }) {
    final data = buf.getChannelData(0).toDart;
    final win = (buf.sampleRate * 0.01).round();
    double? prev;
    var worst = 0.0;
    for (
      var i = (fromSec * buf.sampleRate).round();
      i + win < math.min(data.length, (toSec * buf.sampleRate).round());
      i += win
    ) {
      var e = 0.0;
      for (var k = i; k < i + win; k++) {
        e += data[k] * data[k];
      }
      final db = 10 * math.log(e / win + 1e-12) / math.ln10;
      if (prev != null) worst = math.max(worst, (db - prev).abs());
      prev = db;
    }
    return worst;
  }

  void _copySamplesFrom(_WebPianoSynth other) {
    other._samples.forEach((k, v) => _samples[k] = {...v});
    _drums.addAll(other._drums);
    _softHat = other._softHat;
    for (final k in [...other._samples.keys, 'drums']) {
      _loads[k] = Future.value();
    }
  }

  /// RMS over the whole render, RMS over 50 ms windows above -60 dBFS
  /// (ignores silence), and sample peak, all in dBFS.
  static Map<String, double> _levels(web.AudioBuffer buf) {
    final chans = [
      for (var c = 0; c < buf.numberOfChannels; c++)
        buf.getChannelData(c).toDart,
    ];
    final n = buf.length;
    final win = (buf.sampleRate * 0.05).round();
    var sum = 0.0, peak = 0.0, gatedSum = 0.0;
    var gatedN = 0;
    for (var start = 0; start < n; start += win) {
      final end = math.min(n, start + win);
      var ws = 0.0;
      for (final ch in chans) {
        for (var i = start; i < end; i++) {
          final v = ch[i];
          ws += v * v;
          if (v.abs() > peak) peak = v.abs();
        }
      }
      sum += ws;
      final count = (end - start) * chans.length;
      if (ws / count > 1e-6) {
        gatedSum += ws;
        gatedN += count;
      }
    }
    double db(double x) => x <= 0 ? -120 : 10 * math.log(x) / math.ln10;
    return {
      'rmsDb': db(sum / (n * chans.length)),
      'gatedRmsDb': gatedN == 0 ? -120 : db(gatedSum / gatedN),
      'peakDb': db(peak * peak),
    };
  }
}
