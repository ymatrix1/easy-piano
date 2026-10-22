import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../note_event.dart';
import 'mic_clock.dart';
import 'mic_input.dart';
import 'note_detector.dart';

MicInput createMicInput() => _WebMicInput();

/// getUserMedia → AudioWorklet (web/mic_worklet.js) → [NoteDetector].
class _WebMicInput implements MicInput {
  static const _offsetKey = 'easy_piano.mic_offset_ms';
  static const _preferredKey = 'easy_piano.input';
  static const _deviceKey = 'easy_piano.mic_device';

  final _controller = StreamController<NoteEvent>.broadcast();
  final _raw = StreamController<NoteEvent>.broadcast();
  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  web.AudioWorkletNode? _node;
  NoteDetector? _detector;
  int? _baseFrame;

  /// Trained note model (web/mic_model_worker.js). The DSP [_detector] runs
  /// until the worker reports ready, and again if it fails or falls behind.
  web.Worker? _worker;
  bool _modelReady = false;
  int? _modelBaseFrame;

  /// performance.now() minus context time (ms); see [nextClockOffset].
  double _clockOffset = double.infinity;

  /// Bumped by every start/stop; a start that awaited across a newer
  /// start/stop drops what it opened instead of leaving a live track.
  int _generation = 0;

  @override
  MicError? error;

  @override
  Stream<NoteEvent> get events => _controller.stream;

  @override
  Stream<NoteEvent> get rawEvents => _raw.stream;

  @override
  List<String> get deviceNames => const [];

  @override
  bool get running => _node != null;

  @override
  double level = 0;

  Set<int> _expected = const {};

  @override
  Set<int> get expected => _expected;

  @override
  set expected(Set<int> pitches) {
    _expected = pitches;
    _applyExpected();
  }

  bool _blind = false;

  @override
  bool get blind => _blind;

  @override
  set blind(bool value) {
    _blind = value;
    _applyExpected();
  }

  /// The notes the detectors see: none while [blind].
  Set<int> get _effectiveExpected => _blind ? const {} : _expected;

  void _applyExpected() {
    _detector?.expected = _effectiveExpected;
    _postExpected();
  }

  void _postExpected() {
    final w = _worker;
    if (w == null) return;
    final msg = JSObject()
      ..['type'] = 'expected'.toJS
      ..['pitches'] = [for (final p in _effectiveExpected) p.toJS].toJS;
    w.postMessage(msg);
  }

  static const _modelKey = 'easy_piano.mic_model';

  @override
  bool get modelEnabled {
    try {
      final query = Uri.base.queryParameters['mic'];
      if (query == 'dsp') return false;
      return web.window.localStorage.getItem(_modelKey) != 'off';
    } catch (_) {
      return true;
    }
  }

  @override
  set modelEnabled(bool value) {
    try {
      value
          ? web.window.localStorage.removeItem(_modelKey)
          : web.window.localStorage.setItem(_modelKey, 'off');
    } catch (_) {}
  }

  @override
  bool get modelActive => _modelReady;

  @override
  double? modelFrameMs;

  /// Slow peak follower; input is scaled so quiet mics still reach the
  /// detector's thresholds (gain capped at 8×, adapts over ~10 s so it
  /// doesn't pump between notes). Below the noise gate nothing is analysed.
  double _envelope = 0.01;

  @override
  String? get deviceId {
    try {
      return web.window.localStorage.getItem(_deviceKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> selectDevice(String? id) async {
    try {
      id == null
          ? web.window.localStorage.removeItem(_deviceKey)
          : web.window.localStorage.setItem(_deviceKey, id);
    } catch (_) {}
    if (running) {
      stop();
      await start();
    }
  }

  @override
  Future<List<MicDevice>> devices() async {
    try {
      final list = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      final out = <MicDevice>[];
      for (final d in list.toDart) {
        if (d.kind != 'audioinput' || d.deviceId.isEmpty) continue;
        if (d.deviceId == 'default' || d.deviceId == 'communications') {
          continue;
        }
        out.add(
          MicDevice(
            d.deviceId,
            d.label.isEmpty ? 'Microphone ${out.length + 1}' : d.label,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  double now() => web.window.performance.now();

  String get _offsetKeyForDevice => '$_offsetKey:${deviceId ?? 'default'}';

  @override
  double? get offsetMs {
    try {
      return double.tryParse(
        web.window.localStorage.getItem(_offsetKeyForDevice) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  set offsetMs(double? value) {
    try {
      value == null
          ? web.window.localStorage.removeItem(_offsetKeyForDevice)
          : web.window.localStorage.setItem(_offsetKeyForDevice, '$value');
    } catch (_) {}
  }

  @override
  bool get preferred {
    try {
      return web.window.localStorage.getItem(_preferredKey) == 'mic';
    } catch (_) {
      return false;
    }
  }

  @override
  set preferred(bool value) {
    try {
      web.window.localStorage.setItem(_preferredKey, value ? 'mic' : 'midi');
    } catch (_) {}
  }

  @override
  Future<bool> start() async {
    if (running) return true;
    final gen = ++_generation;
    error = null;
    final devices = (web.window.navigator as JSObject).has('mediaDevices')
        ? web.window.navigator.mediaDevices
        : null;
    if (devices == null || !(web.window as JSObject).has('AudioWorkletNode')) {
      error = MicError.unsupported;
      return false;
    }
    try {
      // Raw signal: echo cancellation, noise suppression and AGC smear piano
      // attacks and pump the level. The app's own piano is muted instead.
      final id = deviceId;
      final audio = web.MediaTrackConstraints(
        echoCancellation: false.toJS,
        noiseSuppression: false.toJS,
        autoGainControl: false.toJS,
      );
      if (id != null) {
        (audio as JSObject)['deviceId'] = {'exact': id}.jsify();
      }
      final stream = await devices
          .getUserMedia(web.MediaStreamConstraints(audio: audio))
          .toDart;
      if (gen != _generation) {
        _stopTracks(stream);
        return false;
      }
      _stream = stream;
    } catch (e) {
      if (gen != _generation) return false;
      // dart2js and dart2wasm both surface the DOMException name in
      // toString() ("NotAllowedError: ..."); avoids JS interop type checks.
      final text = '$e';
      final name = const [
        'NotAllowedError',
        'SecurityError',
        'NotFoundError',
        'OverconstrainedError',
        'NotReadableError',
        'AbortError',
      ].firstWhere(text.contains, orElse: () => '');
      final err = micErrorFor(name);
      // Only a missing remembered device falls back to the default input.
      if (err == MicError.notFound && deviceId != null) {
        try {
          web.window.localStorage.removeItem(_deviceKey);
        } catch (_) {}
        _generation--; // the retry is this same start
        return start();
      }
      error = err;
      return false;
    }
    try {
      final ctx = web.AudioContext(
        web.AudioContextOptions(latencyHint: 'interactive'.toJS),
      );
      _ctx = ctx;
      await ctx.audioWorklet.addModule('mic_worklet.js').toDart;
      if (gen != _generation) {
        ctx.close();
        return false;
      }
      final node = web.AudioWorkletNode(ctx, 'mic-capture');
      ctx.createMediaStreamSource(_stream!).connect(node);
      // Keep the node pulled by the graph; it outputs silence.
      final sink = ctx.createGain()..gain.value = 0;
      node.connect(sink);
      sink.connect(ctx.destination);
      _detector = NoteDetector(sampleRate: ctx.sampleRate)
        ..expected = _effectiveExpected;
      _baseFrame = null;
      _clockOffset = double.infinity;
      node.port.onmessage = _onChunk.toJS;
      _node = node;
      await ctx.resume().toDart;
      if (modelEnabled) _startModel(ctx.sampleRate.toDouble());
    } catch (_) {
      if (gen != _generation) return false;
      stop();
      error = MicError.unsupported;
      return false;
    }
    return true;
  }

  void _onChunk(web.MessageEvent e) {
    final ctx = _ctx;
    final det = _detector;
    if (ctx == null || det == null) return;
    final data = e.data as JSObject;
    final frame = (data.getProperty<JSNumber>('frame'.toJS)).toDartInt;
    final samples = data.getProperty<JSFloat32Array>('samples'.toJS).toDart;
    _baseFrame ??= frame;
    _clockOffset = nextClockOffset(_clockOffset, now(), ctx.currentTime);
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    level = math.min(1, peak * 4);
    _envelope = math.max(peak, _envelope * 0.9995);
    final worker = _worker;
    if (_modelReady && worker != null) {
      // Same slow gain as the DSP path (target peak 0.3, at most 8x, no gate):
      // a quiet laptop mic would otherwise sit below what the model was
      // trained on (recall at -60 dBFS: 0.61 without, 0.84 with).
      final modelGain = math.min(8.0, 0.3 / math.max(_envelope, 0.01));
      _modelBaseFrame ??= frame;
      final msg = JSObject()
        ..['type'] = 'chunk'.toJS
        ..['sampleRate'] = ctx.sampleRate.toJS
        ..['samples'] = Float32List.fromList([
          for (final s in samples) s * modelGain,
        ]).toJS;
      worker.postMessage(msg);
      return;
    }
    final gain = math.min(8.0, 0.3 / math.max(_envelope, 0.01));
    final gated = peak < 0.004;
    final notes = det.process([
      for (final s in samples) gated ? 0.0 : s * gain,
    ]);
    _deliver(notes, _baseFrame!);
  }

  void _startModel(double sampleRate) {
    try {
      final w = web.Worker(
        'mic_model_worker.js'.toJS,
        web.WorkerOptions(type: 'module'),
      );
      _worker = w;
      w.onmessage = ((web.MessageEvent e) {
        if (_worker != w) return;
        final data = e.data as JSObject;
        final type = data.getProperty<JSString>('type'.toJS).toDart;
        switch (type) {
          case 'ready':
            _modelBaseFrame = null;
            _modelReady = true;
            _postExpected();
          case 'notes':
            final base = _modelBaseFrame;
            if (base == null) return;
            final list = data.getProperty<JSArray>('notes'.toJS).toDart;
            _deliver([
              for (final item in list)
                DetectedNote(
                  (item as JSObject)
                      .getProperty<JSNumber>('pitch'.toJS)
                      .toDartInt,
                  item.getProperty<JSBoolean>('on'.toJS).toDart,
                  item.getProperty<JSNumber>('time'.toJS).toDartDouble,
                  item.getProperty<JSNumber>('detectedAt'.toJS).toDartDouble,
                ),
            ], base);
          case 'stats':
            modelFrameMs = data
                .getProperty<JSNumber>('meanMs'.toJS)
                .toDartDouble;
          case 'error' || 'slow':
            _stopModel(); // back to the DSP detector
        }
      }).toJS;
      w.onerror = ((web.Event _) => _stopModel()).toJS;
      final init = JSObject()
        ..['type'] = 'init'.toJS
        ..['sampleRate'] = sampleRate.toJS;
      w.postMessage(init);
    } catch (_) {
      _stopModel();
    }
  }

  void _stopModel() {
    _modelReady = false;
    _modelBaseFrame = null;
    modelFrameMs = null;
    _worker?.terminate();
    _worker = null;
  }

  void _deliver(List<DetectedNote> notes, int baseFrame) {
    final ctx = _ctx;
    if (ctx == null || notes.isEmpty) return;
    final offset = offsetMs ?? 0;
    for (final n in notes) {
      final t = onsetToPerfMs(
        baseFrame: baseFrame,
        sampleRate: ctx.sampleRate,
        onsetSec: n.time,
        clockOffsetMs: _clockOffset,
      );
      final raw = NoteEvent(
        pitch: n.pitch,
        velocity: 80,
        on: n.on,
        timestampMs: t,
      );
      _raw.add(raw);
      _controller.add(
        NoteEvent(
          pitch: n.pitch,
          velocity: 80,
          on: n.on,
          timestampMs: t - offset,
        ),
      );
    }
  }

  static void _stopTracks(web.MediaStream s) =>
      s.getTracks().toDart.forEach((t) => t.stop());

  @override
  void stop() {
    _generation++;
    _node?.port.onmessage = null;
    _node?.disconnect();
    _node = null;
    _stopModel();
    if (_stream != null) _stopTracks(_stream!);
    _stream = null;
    _ctx?.close();
    _ctx = null;
    _detector = null;
    level = 0;
  }
}
