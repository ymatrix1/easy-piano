import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

/// Measurement helpers for `?mixprobe` (D30 stage 3 gates): output levels
/// of an offline render, and key-to-sound latency through a tap worklet.

/// RMS over the whole render, RMS over 50 ms windows above -60 dBFS
/// (ignores silence), and sample peak, all in dBFS.
Map<String, double> probeLevels(web.AudioBuffer buf) {
  final chans = [
    for (var c = 0; c < buf.numberOfChannels; c++) buf.getChannelData(c).toDart,
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

/// Largest sample-to-sample step on channel 0 between two times.
double probeMaxStep(web.AudioBuffer buf, double fromSec, double toSec) {
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
double probeMaxJumpDb(
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

/// Presses a key [presses] times and reports the time from the `noteOn`
/// call until the main thread hears back from a tap on [output] that the
/// first audible sample was rendered (one return message hop included, the
/// same for every synth; the device's own output latency is reported apart).
Future<Map<String, Object>> probeKeyLatency(
  web.AudioContext ctx,
  web.AudioNode output,
  void Function() noteOn,
  void Function() noteOff, {
  int presses = 10,
}) async {
  await ctx.resume().toDart;
  await ctx.audioWorklet.addModule('audio_worklet.js').toDart;
  final tap = web.AudioWorkletNode(
    ctx,
    'level-tap',
    web.AudioWorkletNodeOptions(numberOfInputs: 1, numberOfOutputs: 0),
  );
  output.connect(tap);
  final ms = <double>[];
  try {
    for (var i = 0; i < presses; i++) {
      final heard = Completer<double>();
      tap.port.onmessage = ((web.MessageEvent _) {
        if (!heard.isCompleted) heard.complete(web.window.performance.now());
      }).toJS;
      tap.port.postMessage('probe'.toJS);
      // Let the tap arm (one message hop) before the key goes down.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final t0 = web.window.performance.now();
      noteOn();
      final back = await heard.future.timeout(const Duration(seconds: 2));
      ms.add(back - t0);
      noteOff();
      // Let the release tail die out, so the tap hears only the next key.
      await Future<void>.delayed(const Duration(milliseconds: 4000));
    }
  } finally {
    output.disconnect(tap);
  }
  ms.sort();
  return {
    'presses': ms.length,
    'medianMs': ms[ms.length ~/ 2],
    'p90Ms': ms[(ms.length * 0.9).floor().clamp(0, ms.length - 1)],
    'minMs': ms.first,
    'maxMs': ms.last,
    'baseLatencyMs': ctx.baseLatency * 1000,
    'outputLatencyMs': ctx.outputLatency * 1000,
    'sampleRate': ctx.sampleRate,
  };
}
