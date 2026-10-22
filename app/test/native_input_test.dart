import 'dart:math' as math;
import 'dart:typed_data';

import 'package:easy_piano/input/mic/mic_input.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/input/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Android side (`MidiBridge.kt`, `MicBridge.kt`) is replaced by mock
/// channel handlers; these tests cover the Dart side of the contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  late Map<String, Object? Function(Object? args)> methods;
  final listening = <String, bool>{};

  void mockPlatform() {
    messenger.setMockMethodCallHandler(nativeInput, (call) async {
      final h = methods[call.method];
      if (h == null) throw MissingPluginException();
      return h(call.arguments);
    });
    for (final ch in const [
      'dev.easypiano/midi/events',
      'dev.easypiano/mic/events',
    ]) {
      messenger.setMockMessageHandler(ch, (data) async {
        final call = codec.decodeMethodCall(data);
        listening[ch] = call.method == 'listen';
        return codec.encodeSuccessEnvelope(null);
      });
    }
  }

  void emit(String channel, Object? event) => messenger.handlePlatformMessage(
    channel,
    codec.encodeSuccessEnvelope(event),
    (_) {},
  );

  void emitError(String channel, String code) =>
      messenger.handlePlatformMessage(
        channel,
        codec.encodeErrorEnvelope(code: code, message: code),
        (_) {},
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    listening.clear();
    methods = {};
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(nativeInput, null);
    for (final ch in const [
      'dev.easypiano/midi/events',
      'dev.easypiano/mic/events',
    ]) {
      messenger.setMockMessageHandler(ch, null);
    }
  });

  group('without a platform side', () {
    test('MIDI start is false', () async {
      expect(await createMidiInput().start(), isFalse);
    });

    test('mic start fails as unsupported, no devices', () async {
      final mic = createMicInput();
      expect(await mic.start(), isFalse);
      expect(mic.error, MicError.unsupported);
      expect(await mic.devices(), isEmpty);
      expect(mic.running, isFalse);
    });
  });

  group('NativeClock', () {
    setUp(mockPlatform);
    test('now() follows the platform clock after sync', () async {
      methods['clockMs'] = (_) => 5000.0;
      final clock = NativeClock();
      expect(await clock.sync(), isTrue);
      expect(clock.now(), closeTo(5000, 200));
    });

    test('sync is false when the platform is missing', () async {
      expect(await NativeClock().sync(), isFalse);
    });
  });

  group('native MIDI', () {
    setUp(mockPlatform);
    test('device names and note events come through', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['midiAvailable'] = (_) => true;
      final midi = createMidiInput();
      final events = <NoteEvent>[];
      midi.events.listen(events.add);
      final started = midi.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      emit('dev.easypiano/midi/events', ['d', 'Casio USB-MIDI']);
      emit('dev.easypiano/midi/events', ['n', 60, 90, 1, 1234.5]);
      emit('dev.easypiano/midi/events', ['n', 60, 0, 0, 1500.0]);
      expect(await started, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(midi.deviceNames, ['Casio USB-MIDI']);
      expect(events, hasLength(2));
      expect(events[0].pitch, 60);
      expect(events[0].velocity, 90);
      expect(events[0].on, isTrue);
      expect(events[0].timestampMs, 1234.5);
      expect(events[1].on, isFalse);
    });

    test('start is false when the device has no MIDI service', () async {
      methods['midiAvailable'] = (_) => false;
      expect(await createMidiInput().start(), isFalse);
    });
  });

  group('native mic', () {
    setUp(mockPlatform);
    Float32List sine(double hz, int n) => Float32List.fromList([
      for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * hz * i / 44100),
    ]);

    Map<String, Object?> chunk(Float32List s) => {
      'sampleRate': 44100,
      'endMs': 100.0,
      'samples': s.buffer.asUint8List(),
    };

    test('permission denied reports MicError.denied', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['micPermission'] = (_) => 'denied';
      final mic = createMicInput();
      expect(await mic.start(), isFalse);
      expect(mic.error, MicError.denied);
      expect(listening['dev.easypiano/mic/events'], isNot(true));
    });

    test('granted permission starts capture and measures level', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['micPermission'] = (_) => 'granted';
      methods['micSelect'] = (_) => null;
      final mic = createMicInput();
      final started = mic.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      emit('dev.easypiano/mic/events', chunk(sine(440, 1024)));
      expect(await started, isTrue);
      expect(mic.running, isTrue);
      expect(mic.level, greaterThan(0.5));
      mic.stop();
      expect(mic.running, isFalse);
      expect(mic.level, 0);
    });

    test('a piano-like note after silence produces a note-on', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['micPermission'] = (_) => 'granted';
      methods['micSelect'] = (_) => null;
      const sr = 44100;
      final pcm = Float32List(sr * 2);
      final f0 = 440.0;
      for (var i = 0; i < sr; i++) {
        final t = i / sr;
        final env = math.min(1.0, t / 0.005) * math.exp(-t * 2.5);
        var v = 0.0;
        for (var h = 1; h <= 8; h++) {
          v += math.sin(2 * math.pi * f0 * h * t) / (h * h * 0.7 + 0.3);
        }
        pcm[sr ~/ 2 + i] = 0.15 * env * v;
      }
      final mic = createMicInput();
      final events = <NoteEvent>[];
      mic.events.listen(events.add);
      final started = mic.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (var i = 0; i + 1024 <= pcm.length; i += 1024) {
        emit('dev.easypiano/mic/events', chunk(pcm.sublist(i, i + 1024)));
      }
      await started;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.where((e) => e.on).map((e) => e.pitch), contains(69));
      mic.stop();
    });

    test('platform "busy" error maps to MicError.busy', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['micPermission'] = (_) => 'granted';
      methods['micSelect'] = (_) => null;
      final mic = createMicInput();
      final started = mic.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      emitError('dev.easypiano/mic/events', 'busy');
      expect(await started, isFalse);
      expect(mic.error, MicError.busy);
      expect(mic.running, isFalse);
    });

    test('devices() lists id and label', () async {
      methods['micDevices'] = (_) => [
        {'id': 7, 'label': 'Built-in microphone'},
      ];
      final list = await createMicInput().devices();
      expect(list.single.id, '7');
      expect(list.single.label, 'Built-in microphone');
    });

    test('preferred and per-device offset persist', () async {
      methods['clockMs'] = (_) => 0.0;
      methods['micPermission'] = (_) => 'denied';
      final mic = createMicInput();
      await mic.start(); // loads preferences
      mic.preferred = true;
      mic.offsetMs = 42;
      expect(mic.preferred, isTrue);
      expect(mic.offsetMs, 42);
      await mic.selectDevice('9');
      expect(mic.deviceId, '9');
      expect(mic.offsetMs, isNull); // other device, own calibration
      await mic.selectDevice(null);
      expect(mic.offsetMs, 42);
    });
  });
}
