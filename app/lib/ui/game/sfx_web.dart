import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../audio/piano_synth.dart';
import 'sfx.dart';

/// Menu sounds on web. Musical cues (taps, confirms, stars, win/lose) are
/// short phrases on the app's sampled piano, so menus sound like the same
/// instrument as the lessons (D22). Whooshes are filtered noise. Until the
/// piano samples decode, a small Web Audio synth stands in.
class SfxPlayer {
  web.AudioContext? _ctx;
  web.AudioBuffer? _noise;
  web.GainNode? _master;

  web.AudioContext get _c {
    var ctx = _ctx;
    if (ctx == null) {
      ctx = _ctx = web.AudioContext();
      _master = ctx.createGain()..gain.value = 0.9;
      _master!.connect(ctx.destination);
      final n = (ctx.sampleRate * 0.5).round();
      final data = Float32List(n);
      final rnd = math.Random(3);
      for (var i = 0; i < n; i++) {
        data[i] = rnd.nextDouble() * 2 - 1;
      }
      _noise = ctx.createBuffer(1, n, ctx.sampleRate)
        ..copyToChannel(data.toJS, 0);
    }
    if (ctx.state == 'suspended') ctx.resume();
    return ctx;
  }

  void play(SfxKind kind) {
    pianoSynth.load();
    if (pianoSynth.ready && _piano(kind)) return;
    final ctx = _c;
    if (ctx.state != 'running') return; // no gesture yet: stay silent
    final t = ctx.currentTime + 0.005;
    switch (kind) {
      case SfxKind.hover:
        _noiseBurst(t, 0.03, 0.025, 'bandpass', 5000, 7000);
      case SfxKind.tap:
        _tone(t, 520, 210, 0.08, 0.13, 'triangle');
        _noiseBurst(t, 0.012, 0.05, 'highpass', 3000, 3000);
      case SfxKind.confirm:
        _tone(t, 660, 680, 0.09, 0.11, 'triangle');
        _tone(t + 0.07, 990, 1010, 0.16, 0.11, 'triangle');
        _tone(t + 0.07, 1980, 2000, 0.12, 0.03, 'sine');
      case SfxKind.open:
        _noiseBurst(t, 0.2, 0.07, 'bandpass', 500, 2600);
        _tone(t, 300, 520, 0.12, 0.05, 'sine');
      case SfxKind.close:
        _noiseBurst(t, 0.16, 0.06, 'bandpass', 2400, 500);
        _tone(t, 520, 300, 0.1, 0.05, 'sine');
      case SfxKind.tab:
        _tone(t, 880, 1320, 0.06, 0.08, 'triangle');
      case SfxKind.locked:
        _tone(t, 150, 120, 0.12, 0.08, 'square');
      case SfxKind.star1:
        _bell(t, 1046.5);
      case SfxKind.star2:
        _bell(t, 1318.5);
      case SfxKind.star3:
        _bell(t, 1568.0);
      case SfxKind.win:
        for (final (i, f) in const [523.25, 659.25, 783.99, 1046.5].indexed) {
          _tone(t + i * 0.09, f, f, 0.22, 0.09, 'triangle');
        }
      case SfxKind.lose:
        _tone(t, 392, 380, 0.16, 0.08, 'triangle');
        _tone(t + 0.14, 311, 290, 0.26, 0.08, 'triangle');
    }
  }

  /// Piano phrase for [kind]: (pitch, delay s, duration s, velocity).
  /// Returns false for sounds that stay synthesized (hover and whooshes).
  bool _piano(SfxKind kind) {
    final notes = switch (kind) {
      SfxKind.tap => const [(88, 0.0, 0.12, 38)],
      SfxKind.tab => const [(84, 0.0, 0.15, 44), (91, 0.05, 0.2, 36)],
      SfxKind.confirm => const [(79, 0.0, 0.2, 60), (84, 0.07, 0.4, 70)],
      SfxKind.locked => const [(38, 0.0, 0.25, 70), (39, 0.0, 0.25, 62)],
      SfxKind.star1 => const [(84, 0.0, 1.2, 82), (72, 0.0, 1.2, 50)],
      SfxKind.star2 => const [(88, 0.0, 1.2, 84), (76, 0.0, 1.2, 52)],
      SfxKind.star3 => const [(91, 0.0, 1.4, 88), (79, 0.0, 1.4, 56)],
      SfxKind.win => const [
        (72, 0.0, 0.3, 70),
        (76, 0.09, 0.3, 74),
        (79, 0.18, 0.3, 78),
        (84, 0.27, 1.4, 90),
        (60, 0.27, 1.4, 62),
        (67, 0.27, 1.4, 58),
        (76, 0.27, 1.4, 64),
      ],
      SfxKind.lose => const [
        (67, 0.0, 0.3, 60),
        (63, 0.16, 0.8, 54),
        (55, 0.16, 0.8, 44),
      ],
      SfxKind.hover || SfxKind.open || SfxKind.close => null,
    };
    if (notes == null) return false;
    for (final (pitch, delay, dur, vel) in notes) {
      pianoSynth.schedule(
        pitch,
        delay,
        dur,
        velocity: vel,
        force: true,
        part: 'sfx',
      );
    }
    return true;
  }

  /// Oscillator with an exponential pitch glide and a fast attack, exp decay.
  void _tone(
    double t,
    double f0,
    double f1,
    double dur,
    double vol,
    String type,
  ) {
    final ctx = _c;
    final osc = ctx.createOscillator()..type = type;
    osc.frequency
      ..setValueAtTime(f0, t)
      ..exponentialRampToValueAtTime(f1, t + dur);
    final g = ctx.createGain();
    g.gain
      ..setValueAtTime(0.0001, t)
      ..exponentialRampToValueAtTime(vol, t + 0.006)
      ..exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(g);
    g.connect(_master!);
    osc.start(t);
    osc.stop(t + dur + 0.02);
  }

  /// Filtered noise with a swept cutoff (clicks and whooshes).
  void _noiseBurst(
    double t,
    double dur,
    double vol,
    String filter,
    double fromHz,
    double toHz,
  ) {
    final ctx = _c;
    final src = ctx.createBufferSource()..buffer = _noise;
    final bq = ctx.createBiquadFilter()..type = filter;
    bq.Q.value = 1.2;
    bq.frequency
      ..setValueAtTime(fromHz, t)
      ..exponentialRampToValueAtTime(toHz, t + dur);
    final g = ctx.createGain();
    g.gain
      ..setValueAtTime(0.0001, t)
      ..exponentialRampToValueAtTime(vol, t + dur * 0.3)
      ..exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(bq);
    bq.connect(g);
    g.connect(_master!);
    src.start(t);
    src.stop(t + dur + 0.02);
  }

  /// Bell: fundamental plus an inharmonic partial, long decay.
  void _bell(double t, double f) {
    _tone(t, f, f, 0.7, 0.11, 'sine');
    _tone(t, f * 2.76, f * 2.76, 0.35, 0.035, 'sine');
    _tone(t, f * 5.4, f * 5.4, 0.15, 0.015, 'sine');
  }
}
