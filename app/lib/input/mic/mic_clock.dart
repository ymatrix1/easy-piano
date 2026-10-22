import 'dart:math' as math;

/// Clock mapping for mic onsets (pure, for tests). The worklet reports the
/// AudioContext frame of each chunk; notes are timed on that sample clock
/// and must land on `performance.now()`, the clock MIDI and the session use.

/// Updated estimate of performance.now() − context time (ms). Each chunk is
/// handled some time after the audio clock reached it, so every sample is
/// an upper bound; the smallest seen has the least delay.
double nextClockOffset(double previous, double perfNowMs, double ctxTimeSec) =>
    math.min(previous, perfNowMs - ctxTimeSec * 1000);

/// performance.now() time of an onset [onsetSec] after the first sample fed
/// to the detector, which was context frame [baseFrame]. [calibrationMs] is
/// the student's measured latency, subtracted so the event lands when the
/// key was struck as the student saw the cue.
double onsetToPerfMs({
  required int baseFrame,
  required double sampleRate,
  required double onsetSec,
  required double clockOffsetMs,
  double calibrationMs = 0,
}) =>
    (baseFrame / sampleRate + onsetSec) * 1000 + clockOffsetMs - calibrationMs;
