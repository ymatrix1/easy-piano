import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'piano_synth.dart';
import 'piano_synth_webaudio.dart';
import 'recording_synth.dart';
import 'web_audio_probe.dart';

/// `?audio=webaudio` keeps the D22 Web Audio graph (before/after gates and
/// the blind A/B listen of D30 stage 3).
PianoSynth createPianoSynth() {
  final synth = Uri.base.queryParameters['audio'] == 'webaudio'
      ? createWebAudioPianoSynth()
      : _WorkletPianoSynth();
  // Until a practice screen registers its song: the parity fixture, set as
  // CSV text in `window.epFixture` (audio/tests/fixtures/*_events.csv).
  synth.debugRegisterMixProbe((s, _) => _playFixture(s), 24);
  return synth;
}

void _playFixture(PianoSynth synth) {
  final csv = globalContext.getProperty<JSString?>('epFixture'.toJS)?.toDart;
  for (final line in const LineSplitter().convert(csv ?? '')) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final f = line.split(',');
    final (pitch, at, dur, vel) = (
      int.parse(f[2]),
      double.parse(f[3]),
      double.parse(f[4]),
      int.parse(f[5]),
    );
    switch (f[0]) {
      case 'drum':
        synth.drum(pitch, at, velocity: vel);
      case 'click':
        synth.click(at, accent: pitch == 1);
      case 'bass':
        synth.bass(pitch, at, dur, velocity: vel);
      case 'strings':
        synth.pad(pitch, at, dur, velocity: vel);
      case 'choir':
        synth.choir(pitch, at, dur, velocity: vel);
      default:
        synth.schedule(pitch, at, dur, velocity: vel, force: true, part: f[1]);
    }
  }
}

/// Sample files per instrument: (engine code, folder, lowest octave, highest
/// octave; the top octave has only its C). Same set as native.
const _instruments = {
  'piano': (0, 'assets/piano', 1, 8),
  'bass': (1, 'assets/band/bass', 1, 4),
  'strings': (2, 'assets/band/strings', 3, 6),
  'choir': (3, 'assets/band/choir', 3, 6),
};
const _sampleNames = ['C', 'Eb', 'Gb', 'A'];

/// Engine sample kinds (`audio/web/src/lib.rs`).
const _kindDrum = 4, _kindSoftHat = 5, _kindClick = 6, _kindClickAccent = 7;

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

/// Engine part codes (index into `Part::ALL`); anything else is `piano`.
const _parts = {
  'live': 0,
  'piano': 1,
  'ACC': 2,
  'DRUMS': 3,
  'BASS': 4,
  'PAD': 5,
  'CHOIR': 6,
  'sfx': 7,
};
int _part(String key) => _parts[key] ?? 1;

/// The engine module, fetched once and shared by every context.
Future<JSArrayBuffer>? _wasm;

/// Web: the Rust audio engine (D30) in an AudioWorklet
/// (`web/audio_worklet.js`). The browser decodes the MP3s; this class only
/// hands the engine PCM and timestamped events, like the native synth.
class _WorkletPianoSynth implements PianoSynth {
  _WorkletPianoSynth([this._offline]);

  static const _prefKey = 'easy_piano.sound';
  static const _metronomeKey = 'easy_piano.metronome';

  /// Set for offline renders (mix measurements); null for live playback.
  final web.OfflineAudioContext? _offline;
  web.BaseAudioContext? _ctx;
  web.AudioWorkletNode? _node;
  Future<web.AudioWorkletNode?>? _starting;

  /// Messages sent before the node exists, in order.
  final _pending = <JSAny>[];
  final _loads = <String, Future<void>>{};
  final _pongs = <int, Completer<void>>{};
  var _nextPing = 0;

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
    _start(ctx);
    return ctx;
  }

  Future<web.AudioWorkletNode?> _start(web.BaseAudioContext ctx) =>
      _starting ??= () async {
        try {
          final wasm = await (_wasm ??= web.window
              .fetch('audio_engine.wasm'.toJS)
              .toDart
              .then((r) => r.arrayBuffer().toDart));
          await ctx.audioWorklet.addModule('audio_worklet.js').toDart;
          final node = web.AudioWorkletNode(
            ctx,
            'piano-engine',
            web.AudioWorkletNodeOptions(
              numberOfInputs: 0,
              outputChannelCount: [2.toJS].toJS,
              processorOptions: JSObject()..setProperty('wasm'.toJS, wasm),
            ),
          );
          node.port.onmessage = _onMessage.toJS;
          node.connect(ctx.destination);
          for (final m in _pending) {
            node.port.postMessage(m);
          }
          _pending.clear();
          return _node = node;
        } catch (e) {
          // No worklet or wasm: stay silent.
          web.console.warn('audio engine did not start: $e'.toJS);
          return null;
        }
      }();

  void _onMessage(web.MessageEvent e) {
    final pong = (e.data as JSObject?)?.getProperty<JSNumber?>('pong'.toJS);
    if (pong != null) _pongs.remove(pong.toDartInt)?.complete();
  }

  void _send(List<Object> m) => _post(m.jsify()!);

  void _post(JSAny msg, [List<JSObject> transfer = const []]) {
    final node = _node;
    if (node == null) {
      _context();
      _pending.add(msg);
    } else if (transfer.isEmpty) {
      node.port.postMessage(msg);
    } else {
      node.port.postMessage(msg, transfer.toJS);
    }
  }

  /// Resolves once the worklet ran every message sent before it.
  Future<void> _sync() {
    final id = _nextPing++;
    final done = _pongs[id] = Completer<void>();
    _send(['ping', id]);
    return done.future;
  }

  @override
  Future<void> load() =>
      Future.wait([_loadInstrument('piano'), _loadInstrument('click')]);

  @override
  Future<void> loadParts(Iterable<String> parts) => Future.wait([
    load(),
    for (final p in parts)
      if (_partInstrument[p] case final inst?) _loadInstrument(inst),
  ]);

  /// Wall time of the first piano load, for mix-probe reports.
  int? _loadMs;

  Future<void> _loadInstrument(String name) => _loads[name] ??= _fetch(name);

  Future<void> _fetch(String name) async {
    final watch = Stopwatch()..start();
    final ctx = _context();
    if (await _start(ctx) == null) return;
    final jobs = <Future<void>>[];
    if (name == 'click') {
      jobs
        ..add(_add(ctx, _kindClick, 0, 'assets/band/drums/click.mp3'))
        ..add(
          _add(ctx, _kindClickAccent, 0, 'assets/band/drums/click_accent.mp3'),
        );
    } else if (name == 'drums') {
      for (final MapEntry(key: gm, value: files) in _drumFiles.entries) {
        // Decode in parallel, add in round-robin order.
        final decoded = Future.wait([
          for (final f in files) _decode(ctx, 'assets/band/drums/$f.mp3'),
        ]);
        jobs.add(
          decoded.then((bufs) {
            for (final b in bufs) {
              if (b != null) _addBuffer(_kindDrum, gm, b);
            }
          }),
        );
      }
      jobs.add(
        _add(ctx, _kindSoftHat, 0, 'assets/band/drums/hihat_closed_soft.mp3'),
      );
    } else {
      final (kind, dir, low, high) = _instruments[name]!;
      for (var octave = low; octave <= high; octave++) {
        for (var k = 0; k < _sampleNames.length; k++) {
          if (octave == high && k > 0) break; // top sample is a C
          final pitch = (octave + 1) * 12 + 3 * k;
          jobs.add(
            _add(ctx, kind, pitch, '$dir/${_sampleNames[k]}$octave.mp3'),
          );
        }
      }
    }
    await Future.wait(jobs);
    _send(['commit']);
    // A suspended live context (no user gesture yet) runs no worklet code,
    // so only offline renders wait for the engine to take the samples.
    if (_offline != null) await _sync();
    if (name == 'piano') _loadMs ??= watch.elapsedMilliseconds;
  }

  Future<void> _add(
    web.BaseAudioContext ctx,
    int kind,
    int key,
    String path,
  ) async {
    final b = await _decode(ctx, path);
    if (b != null) _addBuffer(kind, key, b);
  }

  /// Hands decoded PCM to the engine (transferred, not copied); the
  /// AudioBuffer is dropped, so only the engine's 16-bit copy stays.
  void _addBuffer(int kind, int key, web.AudioBuffer b) {
    final chans = [
      for (var c = 0; c < b.numberOfChannels && c < 2; c++) b.getChannelData(c),
    ];
    _post(
      ['sample'.toJS, kind.toJS, key.toJS, b.sampleRate.toJS, chans.toJS].toJS,
      [for (final c in chans) c.getProperty<JSArrayBuffer>('buffer'.toJS)],
    );
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

  static int _vel(int v) => v.clamp(1, 127);

  @override
  void noteOn(int pitch, {int velocity = 90}) {
    if (!enabled) return;
    load();
    _context();
    _send(['on', pitch, _vel(velocity)]);
  }

  @override
  void noteOff(int pitch) {
    if (_ctx != null) _send(['off', pitch]);
  }

  void _note(
    String inst,
    String part,
    int pitch,
    double at,
    double dur,
    int v,
  ) => _send([
    'note',
    _instruments[inst]!.$1,
    _part(part),
    pitch,
    at,
    dur,
    _vel(v),
  ]);

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
    _note('piano', part, pitch, startSec, durSec, velocity);
  }

  @override
  void click(double startSec, {bool accent = false}) =>
      _send(['click', startSec, accent]);

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) =>
      _send(['drum', gmPitch, startSec, _vel(velocity)]);

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _note('bass', 'BASS', pitch, startSec, durSec, velocity);

  @override
  void pad(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _note('strings', 'PAD', pitch, startSec, durSec, velocity);

  @override
  void choir(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _note('choir', 'CHOIR', pitch, startSec, durSec, velocity);

  @override
  void setPartLevel(String part, double level) =>
      _send(['level', _part(part), level]);

  @override
  void stopAll() {
    if (_ctx != null) _send(['stop']);
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
      'epDumpEvents'.toJS,
      (() {
        final rec = RecordingSynth();
        schedule(rec, 0.5);
        return jsonEncode({'durSec': durSec, 'events': rec.events}).toJS;
      }).toJS,
    );
    globalContext.setProperty(
      'epMeasureLatency'.toJS,
      (() => (() async {
        await load();
        return probeKeyLatency(
          _ctx! as web.AudioContext,
          _node!,
          () => noteOn(60, velocity: 100),
          () => noteOff(60),
        );
      }()).then((m) => jsonEncode({...m, 'loadMs': _loadMs}).toJS).toJS).toJS,
    );
    globalContext.setProperty(
      'epMeasureMix'.toJS,
      (() => _measureMix(
        schedule,
        durSec,
      ).then((m) => jsonEncode(m).toJS).toJS).toJS,
    );
  }

  static const _probeParts = ['piano', 'ACC', 'DRUMS', 'BASS', 'PAD', 'CHOIR'];

  /// Same report as the Web Audio probe, rendered through the engine in an
  /// OfflineAudioContext (each render loads its own samples first, so
  /// `*RenderMs` is rendering only).
  Future<Map<String, Object>> _measureMix(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  ) async {
    final out = <String, Object>{'durSec': durSec, 'loadMs': _loadMs ?? -1};
    for (final solo in [null, ..._probeParts]) {
      final watch = Stopwatch();
      final buf = await _renderOffline(durSec, (synth) {
        if (solo != null) {
          for (final p in _probeParts) {
            if (p != solo) synth.setPartLevel(p, 0);
          }
        }
        schedule(synth, 0.5);
      }, watch);
      out['${solo ?? 'mix'}RenderMs'] = watch.elapsedMilliseconds;
      out[solo ?? 'mix'] = probeLevels(buf);
    }
    out['click'] = probeLevels(await _renderOffline(0.5, (s) => s.click(0.1)));
    out['clickAccent'] = probeLevels(
      await _renderOffline(0.5, (s) => s.click(0.1, accent: true)),
    );
    out['liveChord'] = probeLevels(
      await _renderOffline(3, (synth) {
        for (final p in [36, 48, 52, 55, 60, 64, 67, 72]) {
          synth.schedule(p, 0.1, 2, velocity: 127, force: true, part: 'live');
        }
      }),
    );
    // C4 is an exact sample, so seams fall at 0.1 + 2.9 s and every 2.4 s.
    final pad = await _renderOffline(8, (synth) => synth.pad(60, 0.1, 7));
    out['padBodyJumpDb'] = probeMaxJumpDb(pad, fromSec: 1, toSec: 2.9);
    out['padSeamJumpDb'] = [
      probeMaxJumpDb(pad, fromSec: 2.95, toSec: 3.06),
      probeMaxJumpDb(pad, fromSec: 5.35, toSec: 5.46),
    ].reduce((a, b) => a > b ? a : b);
    return out;
  }

  Future<web.AudioBuffer> _renderOffline(
    double seconds,
    void Function(_WorkletPianoSynth synth) play, [
    Stopwatch? watch,
  ]) async {
    const rate = 44100;
    final off = web.OfflineAudioContext(
      web.OfflineAudioContextOptions(
        numberOfChannels: 2,
        length: (seconds * rate).ceil(),
        sampleRate: rate,
      ),
    );
    final synth = _WorkletPianoSynth(off);
    await synth.loadParts(_partInstrument.keys);
    play(synth);
    await synth._sync();
    watch?.start();
    final buf = await off.startRendering().toDart;
    watch?.stop();
    return buf;
  }
}
