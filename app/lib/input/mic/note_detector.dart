import 'dart:math' as math;
import 'dart:typed_data';

/// A note found in microphone audio. [time] is the onset in seconds from the
/// first sample fed; [detectedAt] is when the detector had enough audio to
/// report it (onset + analysis window), also in seconds.
class DetectedNote {
  const DetectedNote(this.pitch, this.on, this.time, this.detectedAt);
  final int pitch;
  final bool on;
  final double time;
  final double detectedAt;

  @override
  String toString() =>
      'DetectedNote($pitch, ${on ? 'on' : 'off'}, ${time.toStringAsFixed(3)})';
}

/// Piano note detector for mic input (docs/specs/input.md, D-mic).
///
/// Pure Dart and clock-free: feed samples, get onsets with sample-accurate
/// times. Two stages:
/// 1. Onset: spectral flux on short frames with an adaptive threshold; the
///    exact onset sample is refined from a short-block energy envelope.
/// 2. Pitch: one long frame just after the onset, minus the spectrum just
///    before it (so still-ringing notes are ignored), then greedy harmonic
///    salience picking with harmonic removal; up to [maxPolyphony] notes.
class NoteDetector {
  NoteDetector({
    required this.sampleRate,
    this.lowPitch = 36,
    this.highPitch = 96,
    this.maxPolyphony = 4,
    this.secondNoteRatio = 0.3,
    this.maxHold = 0.6,
    this.fluxGamma = 100,
    this.fluxRatio = 1.5,
    this.fluxDelta = 3.0,
  }) : _fluxN = _pow2(sampleRate * 0.021),
       _pitchN = _pow2(sampleRate * 0.08) {
    _fluxHop = _fluxN ~/ 2;
    _ring = Float32List(_ringSize);
    _fluxWin = _hann(_fluxN);
    _pitchWin = _hann(_pitchN);
    _prevFlux = Float64List(_fluxN ~/ 2);
  }

  final double sampleRate;
  final int lowPitch;
  final int highPitch;
  final int maxPolyphony;

  /// A further chord note must reach this share of the strongest one's salience.
  final double secondNoteRatio;

  /// Onset threshold: log compression of the flux spectrum, and flux must
  /// exceed recent median × [fluxRatio] + [fluxDelta].
  final double fluxGamma;
  final double fluxRatio;
  final double fluxDelta;

  /// Longest a detected note stays "on", in seconds.
  final double maxHold;

  final int _fluxN;
  final int _pitchN;
  late final int _fluxHop;

  static const _ringSize = 1 << 16;
  late final Float32List _ring;
  int _written = 0; // total samples fed
  int _nextFlux = 0; // sample index where the next flux frame ends

  late final Float64List _fluxWin;
  late final Float64List _pitchWin;
  late Float64List _prevFlux;
  final _fluxHistory = <double>[];
  double _lastFlux = 0;
  bool _rising = false;
  int _lastOnset = -1000000000; // not `-1 << 30`: dart2js shifts are unsigned

  /// Onsets waiting for the analysis window to fill: sample index.
  final _pending = <int>[];

  /// Sounding notes: pitch → (salience at onset, onset sample).
  final _active = <int, (double, int)>{};
  int _nextDecayCheck = 0;

  static int _pow2(double n) {
    var p = 1;
    while (p < n) {
      p <<= 1;
    }
    return p;
  }

  static Float64List _hann(int n) => Float64List.fromList([
    for (var i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / n),
  ]);

  /// Latency from onset to report, in seconds (analysis window + guard).
  double get analysisDelay => (_pitchN + _guard) / sampleRate;

  int get _guard => (sampleRate * 0.012).round();

  /// Feeds mono samples in [-1, 1]; returns notes found so far.
  List<DetectedNote> process(List<double> samples) {
    final out = <DetectedNote>[];
    for (final s in samples) {
      _ring[_written & (_ringSize - 1)] = s;
      _written++;
      if (_written >= _nextFlux + _fluxN) {
        _onFluxFrame(_nextFlux, out);
        _nextFlux += _fluxHop;
      }
      if (_pending.isNotEmpty &&
          _written >= _pending.first + _guard + _pitchN) {
        _analyse(_pending.removeAt(0), out);
      }
      if (_written >= _nextDecayCheck) {
        _nextDecayCheck = _written + _fluxHop * 2;
        _checkDecay(out);
      }
    }
    return out;
  }

  double _sample(int i) => i < 0 || i >= _written || _written - i > _ringSize
      ? 0
      : _ring[i & (_ringSize - 1)];

  Float64List _magnitudes(int start, int n, Float64List win, {int pad = 1}) {
    final size = n * pad;
    final re = Float64List(size);
    final im = Float64List(size);
    for (var i = 0; i < n; i++) {
      re[i] = _sample(start + i) * win[i];
    }
    _fft(re, im);
    final mag = Float64List(size ~/ 2);
    for (var k = 0; k < mag.length; k++) {
      mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]);
    }
    return mag;
  }

  void _onFluxFrame(int start, List<DetectedNote> out) {
    final mag = _magnitudes(start, _fluxN, _fluxWin);
    // Log-compressed positive spectral difference above ~60 Hz.
    final lo = (60 * _fluxN / sampleRate).ceil();
    var flux = 0.0;
    for (var k = lo; k < mag.length; k++) {
      final m = math.log(1 + fluxGamma * mag[k]);
      final d = m - _prevFlux[k];
      if (d > 0) flux += d;
      _prevFlux[k] = m;
    }
    _fluxHistory.add(flux);
    if (_fluxHistory.length > 40) _fluxHistory.removeAt(0);
    final sorted = [..._fluxHistory]..sort();
    final median = sorted[sorted.length ~/ 2];
    final threshold = median * fluxRatio + fluxDelta;
    // Peak picking: report on the frame where flux stops rising.
    final end = start + _fluxN;
    if (flux > threshold && flux > _lastFlux) {
      _rising = true;
    } else if (_rising) {
      _rising = false;
      if (end - _lastOnset > sampleRate * 0.06) {
        final onset = _refineOnset(end - _fluxN - _fluxHop * 2, end);
        _lastOnset = end;
        _pending.add(onset);
      }
    }
    _lastFlux = flux;
  }

  /// Finds the attack inside [from, to): the first 2 ms block whose energy
  /// jumps well above the blocks before it.
  int _refineOnset(int from, int to) {
    final block = math.max(16, (sampleRate * 0.002).round());
    final energies = <double>[];
    for (var b = from; b + block <= to; b += block) {
      var e = 0.0;
      for (var i = b; i < b + block; i++) {
        final s = _sample(i);
        e += s * s;
      }
      energies.add(e / block);
    }
    if (energies.isEmpty) return from;
    var best = 0;
    var bestRatio = 0.0;
    var floor = energies.first;
    for (var i = 1; i < energies.length; i++) {
      final ratio = energies[i] / (floor + 1e-9);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = i;
      }
      floor = math.min(floor * 0.7 + energies[i] * 0.3, energies[i]);
      floor = math.max(floor, 1e-9);
    }
    return from + best * block;
  }

  /// Chord notes that can't be told from [found]'s own partials or leakage:
  /// same key, a semitone, an octave, a twelfth, two octaves.
  static bool _related(int found, int p) {
    final d = (p - found).abs();
    return d <= 1 || (p > found && const {12, 19, 24, 28}.contains(d));
  }

  double _freq(int pitch) => 440 * math.pow(2, (pitch - 69) / 12).toDouble();

  void _analyse(int onset, List<DetectedNote> out) {
    const pad = 2;
    final after = _magnitudes(onset + _guard, _pitchN, _pitchWin, pad: pad);
    final before = _magnitudes(onset - _pitchN, _pitchN, _pitchWin, pad: pad);
    final fresh = Float64List(after.length);
    var peak = 0.0;
    for (var k = 0; k < after.length; k++) {
      // Keep bins that grew: a new or re-struck note jumps several times
      // above its decaying tail; a still-ringing note doesn't.
      final growth = after[k] / (before[k] + 1e-9);
      fresh[k] = after[k] * ((growth - 1.3) / 1.2).clamp(0.0, 1.0);
      if (fresh[k] > peak) peak = fresh[k];
    }
    final at = (_written) / sampleRate;
    final time = onset / sampleRate;
    // A flux peak inside a ringing note (no real new energy) is not an
    // onset, nor is a release thump (the level falls).
    final afterPeak = after.reduce(math.max);
    var sumAfter = 0.0, sumBefore = 0.0;
    for (var k = 0; k < after.length; k++) {
      sumAfter += after[k];
      sumBefore += before[k];
    }
    if (peak < 1e-3 || peak < 0.25 * afterPeak) return;
    if (sumAfter < 0.7 * sumBefore) return;
    final binHz = sampleRate / (_pitchN * pad);
    final peaks = _peaks(fresh, binHz, peak);

    final found = <int>[];
    double? first;
    for (var n = 0; n < maxPolyphony; n++) {
      var bestP = -1;
      var bestS = 0.0;
      for (var p = lowPitch; p <= highPitch; p++) {
        if (found.any((q) => _related(q, p))) continue;
        final s = _salience(peaks, p);
        if (s > bestS) {
          bestS = s;
          bestP = p;
        }
      }
      if (bestP < 0) break;
      if (first == null) {
        if (bestS < 0.05) break;
        first = bestS;
      } else if (bestS < first * secondNoteRatio) {
        break;
      }
      found.add(bestP);
      _removeHarmonics(peaks, bestP);
    }
    for (final p in found) {
      if (_active.containsKey(p)) {
        out.add(DetectedNote(p, false, time, at));
      }
      _active[p] = (_level(after, p, binHz), onset);
      out.add(DetectedNote(p, true, time, at));
    }
  }

  /// Spectral peaks (local maxima above 2% of [peak]) as (Hz, magnitude),
  /// with parabolic interpolation of the frequency.
  List<(double, double)> _peaks(Float64List mag, double binHz, double peak) {
    final out = <(double, double)>[];
    for (var k = 2; k < mag.length - 1; k++) {
      final m = mag[k];
      if (m < peak * 0.02 || m < mag[k - 1] || m <= mag[k + 1]) continue;
      final a = mag[k - 1], c = mag[k + 1];
      final den = a - 2 * m + c;
      final d = den == 0 ? 0.0 : 0.5 * (a - c) / den;
      out.add(((k + d) * binHz, m / peak));
    }
    return out;
  }

  /// Strongest peak within ±[cents] of [f].
  static double _near(List<(double, double)> peaks, double f, double cents) {
    final r = math.pow(2, cents / 1200).toDouble();
    var m = 0.0;
    for (final (pf, pm) in peaks) {
      if (pf >= f / r && pf <= f * r && pm > m) m = pm;
    }
    return m;
  }

  static double _partial(double f0, int h) =>
      f0 * h * math.sqrt(1 + 0.0004 * h * h); // mild inharmonicity

  /// Weighted harmonic sum over spectral peaks. A candidate whose own
  /// fundamental (or, for bass notes, second partial) is missing scores zero,
  /// which rejects sub-octave ghosts; the ±40 cent window keeps semitone
  /// neighbours apart.
  double _salience(List<(double, double)> peaks, int p) {
    final f0 = _freq(p);
    final nyq = sampleRate / 2;
    final h1 = _near(peaks, f0, 40);
    // Bass fundamentals are weak on small mics: accept the 2nd/3rd partial.
    final anchor = p < 52
        ? math.max(
            h1,
            math.max(
              _near(peaks, _partial(f0, 2), 45),
              _near(peaks, _partial(f0, 3), 45),
            ),
          )
        : h1;
    if (anchor < 0.1) return 0;
    var s = 0.0;
    for (var h = 1; h <= 8; h++) {
      final f = _partial(f0, h);
      if (f > nyq * 0.95) break;
      s += _near(peaks, f, 45) / math.pow(h, 0.6);
    }
    // Without its own fundamental a bass candidate is likely a sub-octave
    // ghost of a chord; it only wins when nothing explains the partials better.
    return h1 < 0.1 ? s * 0.5 : s;
  }

  /// Takes a found note's partials out of the peak list (half strength: a
  /// chord note may share one).
  void _removeHarmonics(List<(double, double)> peaks, int p) {
    final f0 = _freq(p);
    for (var i = 0; i < peaks.length; i++) {
      final (pf, pm) = peaks[i];
      final h = (pf / f0).round();
      if (h < 1 || h > 16) continue;
      final f = _partial(f0, h);
      if ((1200 * math.log(pf / f) / math.ln2).abs() < 50) {
        peaks[i] = (pf, h == 1 ? 0 : pm * 0.5);
      }
    }
  }

  /// Fundamental (+ 2nd partial) level used for release detection.
  double _peakNear(Float64List mag, double f, double binHz, double tol) {
    final lo = (f * (1 - tol) / binHz).floor();
    final hi = (f * (1 + tol) / binHz).ceil();
    var m = 0.0;
    for (var k = math.max(1, lo); k <= hi && k < mag.length; k++) {
      if (mag[k] > m) m = mag[k];
    }
    return m;
  }

  double _level(Float64List mag, int p, double binHz) =>
      _peakNear(mag, _freq(p), binHz, 0.025) +
      _peakNear(mag, 2 * _freq(p), binHz, 0.025);

  /// Releases notes whose fundamental fell to a fraction of its onset level.
  void _checkDecay(List<DetectedNote> out) {
    if (_active.isEmpty) return;
    const pad = 2;
    final mag = _magnitudes(_written - _pitchN, _pitchN, _pitchWin, pad: pad);
    final binHz = sampleRate / (_pitchN * pad);
    final now = _written / sampleRate;
    final gone = <int>[];
    _active.forEach((p, v) {
      final age = _written - v.$2;
      if (age < _pitchN * 2) return;
      // A mic can't see the key go up; release on decay, or after
      // [maxHold] so held-looking keys never pile up on screen.
      if (age > maxHold * sampleRate || _level(mag, p, binHz) < v.$1 * 0.12) {
        gone.add(p);
      }
    });
    for (final p in gone) {
      _active.remove(p);
      out.add(DetectedNote(p, false, now, now));
    }
  }

  /// In-place iterative radix-2 FFT.
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang);
      final wi = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0;
        var ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final a = i + k;
          final b = a + len ~/ 2;
          final xr = re[b] * cr - im[b] * ci;
          final xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final t = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = t;
        }
      }
    }
  }
}
