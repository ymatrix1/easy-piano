import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';

/// Dynamics and hairpins of one song, in beats.
class SongMarks {
  const SongMarks({required this.dynamics, required this.hairpins});

  static const empty = SongMarks(dynamics: [], hairpins: []);

  final List<StaffDynamic> dynamics;
  final List<StaffHairpin> hairpins;
}

/// Reads dynamic and hairpin directives from a song JSON string.
///
/// Directives sit in a hand string like notes do (zero length):
/// - `{dyn:"p"}` sets a dynamic at that beat (see [DynamicsLayout.glyphsFor]).
/// - `{cresc}` / `{dim}` open a hairpin at that beat.
/// - `{end}` closes the open hairpin.
///
/// An open hairpin also closes at the next dynamic, the next hairpin, or the
/// end of the song. Unknown dynamic text is ignored here; lint is responsible
/// for rejecting it in content.
abstract final class SongMarksParser {
  static final _dynDirective = RegExp(r'^\{dyn:"([^"]*)"\}$');

  static SongMarks parse(String songJson) {
    if (songJson.isEmpty) return SongMarks.empty;
    try {
      final decoded = jsonDecode(songJson);
      if (decoded is! Map<String, dynamic>) return SongMarks.empty;
      final rawBars = decoded['bars'];
      if (rawBars is! List) return SongMarks.empty;

      final timeSig = decoded['time'] as String? ?? '4/4';
      final parts = timeSig.split('/');
      final num = double.tryParse(parts[0]) ?? 4.0;
      final den = parts.length > 1 ? (double.tryParse(parts[1]) ?? 4.0) : 4.0;

      final events = <_Event>[];
      final seen = <String>{};
      void add(_Event e) {
        // RH and LH often repeat the same directive at the same beat.
        if (seen.add('${e.beat}|${e.kind}|${e.mark}|${e.hairpin}')) {
          events.add(e);
        }
      }

      for (var b = 0; b < rawBars.length; b++) {
        final barMap = rawBars[b];
        if (barMap is! Map) continue;
        final barStart = b * num;

        for (final entry in barMap.entries) {
          final handKey = entry.key.toString();
          if (handKey != 'RH' &&
              handKey != 'LH' &&
              handKey != 'RH2' &&
              handKey != 'LH2') {
            continue;
          }
          var t = 0.0;
          for (final rawTok in SongRestParser.tokenize(
            entry.value.toString(),
          )) {
            final tok = rawTok.trim();
            if (tok.isEmpty) continue;
            final beat = barStart + t;
            if (tok.startsWith('{')) {
              final e = _directive(tok, beat);
              if (e != null) add(e);
              continue;
            }
            final colonIdx = tok.indexOf(':');
            if (colonIdx == -1) continue;
            var tail = tok.substring(colonIdx + 1);
            final parenIdx = tail.indexOf('(');
            if (parenIdx != -1) tail = tail.substring(0, parenIdx);
            final atIdx = tail.indexOf('@');
            if (atIdx != -1) tail = tail.substring(0, atIdx);
            t += SongRestParser.parseDurBeats(tail, den);
          }
        }
      }

      return _build(events, totalBeats: rawBars.length * num);
    } catch (_) {
      // Malformed song: draw no marks rather than break the score.
      return SongMarks.empty;
    }
  }

  static _Event? _directive(String tok, double beat) {
    final dyn = _dynDirective.firstMatch(tok);
    if (dyn != null) {
      final mark = dyn.group(1)!;
      if (DynamicsLayout.glyphsFor(mark) == null) return null;
      return _Event(beat, _Kind.dynamic, mark: mark);
    }
    return switch (tok) {
      '{cresc}' => _Event(beat, _Kind.open, hairpin: HairpinKind.crescendo),
      '{dim}' => _Event(beat, _Kind.open, hairpin: HairpinKind.diminuendo),
      '{end}' => _Event(beat, _Kind.end),
      _ => null,
    };
  }

  static SongMarks _build(List<_Event> events, {required double totalBeats}) {
    events.sort((a, b) => a.beat.compareTo(b.beat));
    final dynamics = <StaffDynamic>[];
    final hairpins = <StaffHairpin>[];

    HairpinKind? openKind;
    var openAt = 0.0;

    void closeAt(double beat) {
      if (openKind == null) return;
      final end = math.min(beat, totalBeats);
      // A zero-length hairpin (closed on the beat it opened) draws nothing.
      if (end > openAt) {
        hairpins.add(
          StaffHairpin(startBeat: openAt, endBeat: end, kind: openKind!),
        );
      }
      openKind = null;
    }

    for (final e in events) {
      switch (e.kind) {
        case _Kind.dynamic:
          closeAt(e.beat);
          dynamics.add(StaffDynamic(e.beat, e.mark!));
        case _Kind.open:
          closeAt(e.beat);
          openKind = e.hairpin;
          openAt = e.beat;
        case _Kind.end:
          closeAt(e.beat);
      }
    }
    closeAt(totalBeats);
    return SongMarks(dynamics: dynamics, hairpins: hairpins);
  }
}

enum _Kind { dynamic, open, end }

class _Event {
  const _Event(this.beat, this.kind, {this.mark, this.hairpin});

  final double beat;
  final _Kind kind;
  final String? mark;
  final HairpinKind? hairpin;
}
