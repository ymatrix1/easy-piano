import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/audio.dart';
import '../src/rust/frb_generated.dart';
import 'piano_synth.dart';

PianoSynth createPianoSynth() => _NativePianoSynth();

/// Sample files per instrument: (bridge kind, folder, lowest octave, highest
/// octave; the top octave has only its C). Same set as the web build.
const _instruments = [
  ('piano', 'assets/piano', 1, 8),
  ('bass', 'assets/band/bass', 1, 4),
  ('strings', 'assets/band/strings', 3, 6),
  ('choir', 'assets/band/choir', 3, 6),
];
const _sampleNames = ['C', 'Eb', 'Gb', 'A'];

/// Drum hits by General MIDI number, in round-robin order.
const _drumFiles = {
  36: ['kick', 'kick_2', 'kick_3'],
  38: ['snare', 'snare_2', 'snare_3'],
  42: ['hihat_closed', 'hihat_closed_2', 'hihat_closed_3'],
  46: ['hihat_open'],
  49: ['crash'],
};

/// Instrument each score part needs.
const _partInstrument = {
  'BASS': 'bass',
  'PAD': 'strings',
  'CHOIR': 'choir',
  'DRUMS': 'drums',
};

/// Android, iOS and desktop: the Rust audio engine (D30) playing through
/// the platform's audio output. Until the engine starts (or if it can't,
/// e.g. in widget tests without the Rust library) every call is silent.
class _NativePianoSynth implements PianoSynth {
  static const _prefKey = 'easy_piano.sound';
  static const _metronomeKey = 'easy_piano.metronome';

  bool _enabled = true;
  bool _metronome = true;
  bool _ready = false;
  Future<bool>? _starting;
  final _loads = <String, Future<void>>{};

  _NativePianoSynth() {
    SharedPreferences.getInstance()
        .then((p) {
          _enabled = p.getBool(_prefKey) ?? true;
          _metronome = p.getBool(_metronomeKey) ?? true;
        })
        .catchError((_) {});
  }

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_prefKey, value))
        .catchError((_) => false);
    if (!value) stopAll();
  }

  @override
  bool get metronome => _metronome;

  @override
  set metronome(bool value) {
    _metronome = value;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_metronomeKey, value))
        .catchError((_) => false);
  }

  Future<bool> _start() => _starting ??= () async {
    try {
      await audioStart();
      return _ready = true;
    } catch (_) {
      return false;
    }
  }();

  @override
  Future<void> load() => _noBridge
      ? Future.value()
      : Future.wait([_loadInstrument('piano'), _loadInstrument('click')]);

  /// No Rust library (widget tests): stay silent without waiting.
  bool get _noBridge {
    try {
      return !RustLib.instance.initialized;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> loadParts(Iterable<String> parts) => _noBridge
      ? Future.value()
      : Future.wait([
          load(),
          for (final p in parts)
            if (_partInstrument[p] case final inst?) _loadInstrument(inst),
        ]);

  Future<void> _loadInstrument(String name) => _loads[name] ??= _fetch(name);

  Future<void> _fetch(String name) async {
    if (!await _start()) {
      // Not cached: a later call (another test, a retry) tries again.
      _starting = null;
      _loads.remove(name);
      return;
    }
    final jobs = <Future<void>>[];
    if (name == 'click') {
      jobs
        ..add(_add('click', 0, 'assets/band/drums/click.mp3'))
        ..add(_add('click_accent', 0, 'assets/band/drums/click_accent.mp3'));
    } else if (name == 'drums') {
      // Round-robin order matters, so each drum's hits go in one by one.
      for (final MapEntry(key: gm, value: files) in _drumFiles.entries) {
        jobs.add(() async {
          for (final f in files) {
            await _add('drum', gm, 'assets/band/drums/$f.mp3');
          }
        }());
      }
      jobs.add(_add('soft_hat', 0, 'assets/band/drums/hihat_closed_soft.mp3'));
    } else {
      final (kind, dir, low, high) = _instruments.firstWhere(
        (i) => i.$1 == name,
      );
      for (var octave = low; octave <= high; octave++) {
        for (var k = 0; k < _sampleNames.length; k++) {
          if (octave == high && k > 0) break; // top sample is a C
          final pitch = (octave + 1) * 12 + 3 * k;
          jobs.add(_add(kind, pitch, '$dir/${_sampleNames[k]}$octave.mp3'));
        }
      }
    }
    await Future.wait(jobs);
    _call(audioCommit);
  }

  /// Decodes one bundled MP3 into the engine's bank (on a Rust worker).
  Future<void> _add(String kind, int key, String path) async {
    try {
      final data = await rootBundle.load(path);
      await audioAddSample(
        kind: kind,
        key: key,
        mp3: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      // A missing sample leaves a gap; neighbours cover it.
    }
  }

  /// Runs a bridge call once the engine is up; sound is decoration, so a
  /// failure never reaches the UI.
  void _call(void Function() f) {
    if (!_ready) return;
    try {
      f();
    } catch (_) {}
  }

  static int _vel(int v) => v.clamp(1, 127);

  @override
  void noteOn(int pitch, {int velocity = 90}) {
    if (!enabled) return;
    load();
    _call(() => audioNoteOn(pitch: pitch, velocity: _vel(velocity)));
  }

  @override
  void noteOff(int pitch) => _call(() => audioNoteOff(pitch: pitch));

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
    _call(
      () => audioNote(
        instrument: 'piano',
        part_: part,
        pitch: pitch,
        startSec: startSec,
        durSec: durSec,
        velocity: _vel(velocity),
      ),
    );
  }

  @override
  void click(double startSec, {bool accent = false}) =>
      _call(() => audioClick(startSec: startSec, accent: accent));

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) => _call(
    () => audioDrum(gm: gmPitch, startSec: startSec, velocity: _vel(velocity)),
  );

  void _band(
    String inst,
    String part,
    int pitch,
    double at,
    double dur,
    int v,
  ) => _call(
    () => audioNote(
      instrument: inst,
      part_: part,
      pitch: pitch,
      startSec: at,
      durSec: dur,
      velocity: _vel(v),
    ),
  );

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _band('bass', 'BASS', pitch, startSec, durSec, velocity);

  @override
  void pad(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _band('strings', 'PAD', pitch, startSec, durSec, velocity);

  @override
  void choir(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _band('choir', 'CHOIR', pitch, startSec, durSec, velocity);

  @override
  void setPartLevel(String part, double level) =>
      _call(() => audioSetPartLevel(part_: part, level: level));

  @override
  void stopAll() => _call(audioStopAll);

  @override
  Future<void> resumeAudio() => _noBridge ? Future.value() : _start();

  @override
  set onStateChange(void Function()? callback) {}

  @override
  void debugRegisterMixProbe(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  ) {}
}
