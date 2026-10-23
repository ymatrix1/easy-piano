import 'package:easy_piano/input/mic/mic_clock.dart';
import 'package:easy_piano/input/mic/mic_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock offset keeps the least-delayed sample', () {
    var off = double.infinity;
    // Audio clock 1.000 s handled at perf 5030 ms (30 ms late), then 1.010 s
    // at 5012 ms (2 ms late), then 1.020 s at 5060 ms (40 ms late).
    off = nextClockOffset(off, 5030, 1.000);
    off = nextClockOffset(off, 5012, 1.010);
    off = nextClockOffset(off, 5060, 1.020);
    expect(off, closeTo(4002, 1e-9));
  });

  test('onset maps frame + detector time onto performance.now()', () {
    // First chunk was frame 48000 (1 s at 48 kHz); onset 0.25 s later.
    final t = onsetToPerfMs(
      baseFrame: 48000,
      sampleRate: 48000,
      onsetSec: 0.25,
      clockOffsetMs: 4002,
    );
    expect(t, closeTo(1250 + 4002, 1e-9));
    final calibrated = onsetToPerfMs(
      baseFrame: 48000,
      sampleRate: 48000,
      onsetSec: 0.25,
      clockOffsetMs: 4002,
      calibrationMs: 120,
    );
    expect(calibrated, closeTo(t - 120, 1e-9));
  });

  test('getUserMedia errors map to what the student can fix', () {
    expect(micErrorFor('NotAllowedError'), MicError.denied);
    expect(micErrorFor('SecurityError'), MicError.denied);
    expect(micErrorFor('NotFoundError'), MicError.notFound);
    expect(micErrorFor('OverconstrainedError'), MicError.notFound);
    expect(micErrorFor('NotReadableError'), MicError.busy);
    expect(micErrorFor('TypeError'), MicError.unsupported);
  });
}
