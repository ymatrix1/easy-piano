import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/ottava_layout.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';

/// Dynamics, hairpins and ottava spanners of one song, in beats.
class SongMarks {
  const SongMarks({
    required this.dynamics,
    required this.hairpins,
    this.ottavas = const [],
  });

  static const empty = SongMarks(dynamics: [], hairpins: [], ottavas: []);

  final List<StaffDynamic> dynamics;
  final List<StaffHairpin> hairpins;

  /// Ottava spanners (`8va` / `8vb`), one hand each.
  final List<StaffOttava> ottavas;
}

/// Reads dynamic, hairpin and ottava directives from a song JSON string.
///
/// Directives sit in a hand string like notes do (zero length):
/// - `{dyn:"p"}` sets a dynamic at that beat (see [DynamicsLayout.glyphsFor]).
/// - `{cresc}` / `{dim}` open a hairpin at that beat.
/// - `{end}` closes the open hairpin.
/// - `{ottava:"8va"}` / `{ottava:"8vb"}` start an ottava on that hand
///   (see [OttavaKind]); `{ottava_end}` stops the hand's open ottava.
///
/// An open hairpin also closes at the next dynamic, the next hairpin, or the
/// end of the song. An open ottava closes at the next ottava start or end on
/// the same hand, or at the end of the song. Unknown dynamic text and unknown
/// ottava text are ignored here; lint is responsible for rejecting them in
/// content.
abstract final class SongMarksParser {
  static final _dynDirective = RegExp(r'^\{dyn:"([^"]*)"\}$');
  static final _ottavaDirective = RegExp(r'^\{ottava:"(8va|8vb)"\}$');

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
      final index = <String, int>{};
      void add(_Event e) {
        // Ottava events are per hand: never merged across hands.
        if (e.kind == _Kind.ottavaStart || e.kind == _Kind.ottavaEnd) {
          events.add(e);
          return;
        }
        // RH and LH often repeat the same directive at the same beat. Keep one
        // event, on the treble staff when either hand carries it.
        final key = '${e.beat}|${e.kind}|${e.mark}|${e.hairpin}';
        final at = index[key];
        if (at == null) {
          index[key] = events.length;
          events.add(e);
        } else if (events[at].leftHand && !e.leftHand) {
          events[at] = e;
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
          final isLh = handKey.startsWith('LH');
          var t = 0.0;
          for (final rawTok in SongRestParser.tokenize(
            entry.value.toString(),
          )) {
            final tok = rawTok.trim();
            if (tok.isEmpty) continue;
            final beat = barStart + t;
            if (tok.startsWith('{')) {
              final e = _directive(tok, beat);
              if (e != null) add(e.withHand(isLh));
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
    final ot = _ottavaDirective.firstMatch(tok);
    if (ot != null) {
      return _Event(beat, _Kind.ottavaStart, mark: ot.group(1));
    }
    return switch (tok) {
      '{cresc}' => _Event(beat, _Kind.open, hairpin: HairpinKind.crescendo),
      '{dim}' => _Event(beat, _Kind.open, hairpin: HairpinKind.diminuendo),
      '{end}' => _Event(beat, _Kind.end),
      '{ottava_end}' => _Event(beat, _Kind.ottavaEnd),
      _ => null,
    };
  }

  static SongMarks _build(List<_Event> events, {required double totalBeats}) {
    final ottavas = _buildOttavas(events, totalBeats: totalBeats);
    events.sort((a, b) => a.beat.compareTo(b.beat));
    final dynamics = <StaffDynamic>[];
    final hairpins = <StaffHairpin>[];

    HairpinKind? openKind;
    var openAt = 0.0;
    var openLeftHand = false;

    void closeAt(double beat) {
      if (openKind == null) return;
      final end = math.min(beat, totalBeats);
      // A zero-length hairpin (closed on the beat it opened) draws nothing.
      if (end > openAt) {
        hairpins.add(
          StaffHairpin(
            startBeat: openAt,
            endBeat: end,
            kind: openKind!,
            leftHand: openLeftHand,
          ),
        );
      }
      openKind = null;
    }

    for (final e in events) {
      switch (e.kind) {
        case _Kind.dynamic:
          closeAt(e.beat);
          dynamics.add(StaffDynamic(e.beat, e.mark!, leftHand: e.leftHand));
        case _Kind.open:
          closeAt(e.beat);
          openKind = e.hairpin;
          openAt = e.beat;
          openLeftHand = e.leftHand;
        case _Kind.end:
          closeAt(e.beat);
        case _Kind.ottavaStart || _Kind.ottavaEnd:
          // Handled by _buildOttavas.
          break;
      }
    }
    closeAt(totalBeats);
    return SongMarks(dynamics: dynamics, hairpins: hairpins, ottavas: ottavas);
  }

  /// Ottava spans per hand. Events are taken in insertion order (source order)
  /// for equal beats, so `{ottava_end}` then `{ottava:"8va"}` on one beat
  /// restarts the spanner, while a start with nothing to end just opens one.
  static List<StaffOttava> _buildOttavas(
    List<_Event> events, {
    required double totalBeats,
  }) {
    final ordered =
        events.indexed
            .where(
              (p) =>
                  p.$2.kind == _Kind.ottavaStart ||
                  p.$2.kind == _Kind.ottavaEnd,
            )
            .toList()
          ..sort((a, b) {
            final c = a.$2.beat.compareTo(b.$2.beat);
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });

    final out = <StaffOttava>[];
    // Open spanner per hand: (kind, start beat).
    final open = <bool, (OttavaKind, double)>{};

    void closeHand(bool leftHand, double beat) {
      final cur = open.remove(leftHand);
      if (cur == null) return;
      final end = math.min(beat, totalBeats);
      // A zero-length spanner draws nothing.
      if (end > cur.$2) {
        out.add(
          StaffOttava(
            kind: cur.$1,
            startBeat: cur.$2,
            endBeat: end,
            leftHand: leftHand,
          ),
        );
      }
    }

    for (final (_, e) in ordered) {
      closeHand(e.leftHand, e.beat);
      if (e.kind == _Kind.ottavaStart) {
        final kind = e.mark == '8vb' ? OttavaKind.bassa : OttavaKind.alta;
        open[e.leftHand] = (kind, e.beat);
      }
    }
    closeHand(false, totalBeats);
    closeHand(true, totalBeats);
    return out;
  }
}

enum _Kind { dynamic, open, end, ottavaStart, ottavaEnd }

class _Event {
  const _Event(
    this.beat,
    this.kind, {
    this.mark,
    this.hairpin,
    this.leftHand = false,
  });

  final double beat;
  final _Kind kind;
  final String? mark;
  final HairpinKind? hairpin;
  final bool leftHand;

  _Event withHand(bool lh) =>
      _Event(beat, kind, mark: mark, hairpin: hairpin, leftHand: lh);
}
