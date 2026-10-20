import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../note_event.dart';
import 'mic_input.dart';
import 'note_detector.dart';

MicInput createMicInput() => _WebMicInput();

/// getUserMedia → AudioWorklet (web/mic_worklet.js) → [NoteDetector].
class _WebMicInput implements MicInput {
  static const _offsetKey = 'easy_piano.mic_offset_ms';
  static const _preferredKey = 'easy_piano.input';

  final _controller = StreamController<NoteEvent>.broadcast();
  final _raw = StreamController<NoteEvent>.broadcast();
  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  web.AudioWorkletNode? _node;
  NoteDetector? _detector;
  int? _baseFrame;

  /// performance.now() minus context time (ms); the smallest value seen is
  /// the one with the least message delay.
  double _clockOffset = double.infinity;

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
  double now() => web.window.performance.now();

  @override
  double? get offsetMs {
    try {
      return double.tryParse(web.window.localStorage.getItem(_offsetKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  @override
  set offsetMs(double? value) {
    try {
      value == null
          ? web.window.localStorage.removeItem(_offsetKey)
          : web.window.localStorage.setItem(_offsetKey, '$value');
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
      final audio = web.MediaTrackConstraints(
        echoCancellation: false.toJS,
        noiseSuppression: false.toJS,
        autoGainControl: false.toJS,
      );
      _stream = await devices
          .getUserMedia(web.MediaStreamConstraints(audio: audio))
          .toDart;
    } catch (_) {
      error = MicError.denied;
      return false;
    }
    try {
      final ctx = web.AudioContext(
        web.AudioContextOptions(latencyHint: 'interactive'.toJS),
      );
      _ctx = ctx;
      await ctx.audioWorklet.addModule('mic_worklet.js').toDart;
      final node = web.AudioWorkletNode(ctx, 'mic-capture');
      ctx.createMediaStreamSource(_stream!).connect(node);
      // Keep the node pulled by the graph; it outputs silence.
      final sink = ctx.createGain()..gain.value = 0;
      node.connect(sink);
      sink.connect(ctx.destination);
      _detector = NoteDetector(sampleRate: ctx.sampleRate);
      _baseFrame = null;
      _clockOffset = double.infinity;
      node.port.onmessage = _onChunk.toJS;
      _node = node;
      await ctx.resume().toDart;
    } catch (_) {
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
    _clockOffset = math.min(_clockOffset, now() - ctx.currentTime * 1000);
    final notes = det.process(samples);
    if (notes.isEmpty) return;
    final offset = offsetMs ?? 0;
    for (final n in notes) {
      final ctxMs = (_baseFrame! / ctx.sampleRate + n.time) * 1000;
      final t = ctxMs + _clockOffset;
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

  @override
  void stop() {
    _node?.port.onmessage = null;
    _node?.disconnect();
    _node = null;
    _stream?.getTracks().toDart.forEach((t) => t.stop());
    _stream = null;
    _ctx?.close();
    _ctx = null;
    _detector = null;
  }
}
