import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native_bridge.dart';
import '../note_event.dart';
import 'mic_clock.dart';
import 'mic_input.dart';
import 'note_detector.dart';

MicInput createMicInput() => _NativeMicInput();

/// AudioRecord (`MicBridge.kt`) → float PCM chunks → [NoteDetector] in Dart,
/// the same detector and gain staging as the web input. Without the platform
/// side (iOS, desktop) [start] fails with [MicError.unsupported].
class _NativeMicInput implements MicInput {
  static const _offsetKey = 'easy_piano.mic_offset_ms';
  static const _preferredKey = 'easy_piano.input';
  static const _deviceKey = 'easy_piano.mic_device';

  final _controller = StreamController<NoteEvent>.broadcast();
  final _raw = StreamController<NoteEvent>.broadcast();
  SharedPreferences? _prefs;
  StreamSubscription<dynamic>? _sub;
  NoteDetector? _detector;
  int _frames = 0;
  double _sampleRate = 44100;
  double _clockOffset = double.infinity;
  int _generation = 0;

  @override
  MicError? error;

  @override
  double level = 0;

  double _envelope = 0.01;
  Set<int> _expected = const {};

  @override
  Stream<NoteEvent> get events => _controller.stream;

  @override
  Stream<NoteEvent> get rawEvents => _raw.stream;

  @override
  List<String> get deviceNames => const [];

  @override
  bool get running => _sub != null;

  @override
  Set<int> get expected => _expected;

  @override
  set expected(Set<int> pitches) {
    _expected = pitches;
    _detector?.expected = pitches;
  }

  @override
  double now() => nativeClock.now();

  Future<SharedPreferences> _loadPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  String get _offsetKeyForDevice => '$_offsetKey:${deviceId ?? 'default'}';

  @override
  double? get offsetMs => _prefs?.getDouble(_offsetKeyForDevice);

  @override
  set offsetMs(double? value) {
    final p = _prefs;
    if (p == null) return;
    value == null
        ? p.remove(_offsetKeyForDevice)
        : p.setDouble(_offsetKeyForDevice, value);
  }

  @override
  bool get preferred => _prefs?.getString(_preferredKey) == 'mic';

  @override
  set preferred(bool value) =>
      _prefs?.setString(_preferredKey, value ? 'mic' : 'midi');

  @override
  String? get deviceId => _prefs?.getString(_deviceKey);

  @override
  Future<void> selectDevice(String? id) async {
    final p = await _loadPrefs();
    id == null ? await p.remove(_deviceKey) : await p.setString(_deviceKey, id);
    if (running) {
      stop();
      await start();
    }
  }

  @override
  Future<List<MicDevice>> devices() async {
    try {
      final list = await nativeInput.invokeListMethod<Map>('micDevices');
      return [
        for (final d in list ?? const <Map>[])
          MicDevice('${d['id']}', d['label'] as String),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> start() async {
    if (running) return true;
    final gen = ++_generation;
    error = null;
    await _loadPrefs();
    try {
      if (!await nativeClock.sync()) {
        error = MicError.unsupported;
        return false;
      }
      final perm = await nativeInput.invokeMethod<String>('micPermission');
      if (perm != 'granted') {
        error = MicError.denied;
        return false;
      }
      await nativeInput.invokeMethod<void>(
        'micSelect',
        int.tryParse(deviceId ?? ''),
      );
    } on MissingPluginException {
      error = MicError.unsupported;
      return false;
    }
    if (gen != _generation) return false;
    final started = Completer<bool>();
    _frames = 0;
    _clockOffset = double.infinity;
    _detector = null;
    _sub = nativeMicEvents.receiveBroadcastStream().listen(
      (chunk) {
        if (!started.isCompleted) started.complete(true);
        _onChunk(chunk as Map<dynamic, dynamic>);
      },
      onError: (Object e) {
        error = e is PlatformException && e.code == 'denied'
            ? MicError.denied
            : e is PlatformException && e.code == 'busy'
            ? MicError.busy
            : MicError.unsupported;
        if (!started.isCompleted) started.complete(false);
        stop();
      },
    );
    final ok = await started.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    if (!ok) {
      error ??= MicError.busy;
      stop();
    }
    return ok && gen == _generation;
  }

  void _onChunk(Map<dynamic, dynamic> msg) {
    final rate = (msg['sampleRate'] as num).toDouble();
    final endMs = (msg['endMs'] as num).toDouble();
    final bytes = msg['samples'] as Uint8List;
    final samples = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final det = _detector ??= NoteDetector(sampleRate: rate)
      ..expected = _expected;
    _sampleRate = rate;
    _frames += samples.length;
    // The chunk ended at endMs; its last sample is frame _frames.
    _clockOffset = nextClockOffset(_clockOffset, endMs, _frames / rate);
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    level = math.min(1, peak * 4);
    _envelope = math.max(peak, _envelope * 0.9995);
    final gain = math.min(8.0, 0.3 / math.max(_envelope, 0.01));
    final gated = peak < 0.004;
    final notes = det.process([
      for (final s in samples) gated ? 0.0 : s * gain,
    ]);
    if (notes.isEmpty) return;
    final offset = offsetMs ?? 0;
    for (final n in notes) {
      final t = onsetToPerfMs(
        baseFrame: 0,
        sampleRate: _sampleRate,
        onsetSec: n.time,
        clockOffsetMs: _clockOffset,
      );
      _raw.add(
        NoteEvent(pitch: n.pitch, velocity: 80, on: n.on, timestampMs: t),
      );
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
    _generation++;
    _sub?.cancel();
    _sub = null;
    _detector = null;
    level = 0;
  }
}
