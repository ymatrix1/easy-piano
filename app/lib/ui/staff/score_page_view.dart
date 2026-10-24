import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/piano_synth.dart';
import '../game/game_theme.dart';
import 'music_font.dart';
import 'score_page_layout.dart';
import 'score_pdf_printer.dart';
import 'staff_note.dart';
import 'staff_painter.dart';

/// Full interactive score visualizer (sightread.dev / Flowkey parity & Easy Piano visual style):
/// - Clean edge-to-edge responsive layout matching sightread.dev (no wasted black borders)
/// - Authentic diatonic pitch mapping with correct G/F clef coordinates and ledgers
/// - Multi-system justified pages with measure numbering
/// - Real-time animated playhead / cursor tracking musical beat time across systems and pages
/// - Transport Bar styled with Easy Piano game theme (Play/Pause, Scrub timeline, Speed modifier, Metronome)
/// - High-resolution PDF export & Print
class ScorePageView extends StatefulWidget {
  const ScorePageView({
    super.key,
    required this.notes,
    required this.totalBeats,
    this.beatsPerBar = 4.0,
    this.keyFifths = 0,
    this.bpm = 100.0,
    this.staves = Staves.grand,
    this.title = '',
    this.composer = '',
    this.onClose,
  });

  final List<StaffNote> notes;
  final double totalBeats;
  final double beatsPerBar;
  final int keyFifths;
  final double bpm;
  final Staves staves;
  final String title;
  final String composer;
  final VoidCallback? onClose;

  @override
  State<ScorePageView> createState() => _ScorePageViewState();
}

class _ScorePageViewState extends State<ScorePageView>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final Ticker _ticker;

  int _currentPage = 0;
  double _scale = 1.0;
  bool _isPlaying = false;
  double _currentBeat = 0.0;
  double _speedModifier = 1.0;
  bool _metronomeOn = false;

  double _lastTickMs = 0.0;
  double _lastMetronomeBeat = -1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pageController.dispose();
    pianoSynth.stopAll();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_isPlaying) return;
    final nowMs = elapsed.inMicroseconds / 1000.0;
    if (_lastTickMs == 0.0) {
      _lastTickMs = nowMs;
      return;
    }

    final deltaSec = (nowMs - _lastTickMs) / 1000.0;
    _lastTickMs = nowMs;

    final effectiveBpm = widget.bpm * _speedModifier;
    final beatsPerSec = effectiveBpm / 60.0;
    final nextBeat = _currentBeat + deltaSec * beatsPerSec;

    if (_metronomeOn) {
      final curBarBeat = nextBeat.floorToDouble();
      if (curBarBeat > _lastMetronomeBeat) {
        _lastMetronomeBeat = curBarBeat;
        final accent = curBarBeat % widget.beatsPerBar == 0;
        pianoSynth.click(0, accent: accent);
      }
    }

    // Play note audio as playhead reaches notes
    for (final n in widget.notes) {
      if (n.isRest || n.isSpacer) continue;
      if (_currentBeat <= n.beat && nextBeat > n.beat) {
        pianoSynth.noteOn(n.pitch, velocity: 85);
      }
    }

    if (nextBeat >= widget.totalBeats) {
      setState(() {
        _currentBeat = widget.totalBeats;
        _isPlaying = false;
        _ticker.stop();
        _lastTickMs = 0.0;
      });
      return;
    }

    setState(() {
      _currentBeat = nextBeat;
    });
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        if (_currentBeat >= widget.totalBeats) {
          _currentBeat = 0.0;
          _lastMetronomeBeat = -1.0;
        }
        _lastTickMs = 0.0;
        _ticker.start();
      } else {
        _ticker.stop();
        pianoSynth.stopAll();
      }
    });
  }

  void _seekToBeat(double beat) {
    setState(() {
      _currentBeat = beat.clamp(0.0, widget.totalBeats);
      _lastMetronomeBeat = _currentBeat.floorToDouble() - 1.0;
    });
  }

  void _printScore(List<ScorePage> pages, ScorePageConfig config) {
    ScorePdfPrinter.printScore(
      pages: pages,
      config: config,
      staves: widget.staves,
      keyFifths: widget.keyFifths,
      beatsPerBar: widget.beatsPerBar,
      title: widget.title,
      composer: widget.composer,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fully responsive sheet width matching sightread.dev (expands to fill the window)
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;

        // On desktop/tablet, score expands edge-to-edge with standard padding
        final sheetWidth = math.max(640.0, availableW - 48.0);
        final sheetHeight = math.max(780.0, availableH - 128.0);

        final config = ScorePageConfig(
          pageWidth: sheetWidth,
          pageHeight: sheetHeight,
          marginTop: 48.0,
          marginBottom: 40.0,
          marginLeft: 36.0,
          marginRight: 36.0,
          grandStaffHeight: 140.0,
          systemDistance: 64.0,
          minMeasureWidth: 110.0,
          systemHeaderWidth: 70.0,
        );

        final pages = ScorePageLayout.layoutScore(
          notes: widget.notes,
          beatsPerBar: widget.beatsPerBar,
          totalBeats: widget.totalBeats,
          config: config,
        );

        // Auto-page turn following playhead
        if (_isPlaying && pages.isNotEmpty) {
          for (var p = 0; p < pages.length; p++) {
            if (_currentBeat >= pages[p].startBeat &&
                _currentBeat <= pages[p].endBeat) {
              if (_currentPage != p && _pageController.hasClients) {
                _pageController.animateToPage(
                  p,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOut,
                );
              }
              break;
            }
          }
        }

        final currentMeasureNum = widget.beatsPerBar > 0
            ? (_currentBeat / widget.beatsPerBar).floor() + 1
            : 1;

        return Scaffold(
          // Warm ivory canvas background matching sightread.dev
          backgroundColor: const Color(0xFFF7F5F0),
          appBar: _buildTopBar(pages.length, pages, config),
          body: Column(
            children: [
              Expanded(
                child: pages.isEmpty
                    ? const Center(
                        child: Text(
                          'No score data available',
                          style: TextStyle(color: GameColors.ink, fontSize: 16),
                        ),
                      )
                    : Transform.scale(
                        scale: _scale,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: pages.length,
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                          itemBuilder: (context, index) {
                            final page = pages[index];
                            return Center(
                              child: SingleChildScrollView(
                                child: ScorePageSheet(
                                  page: page,
                                  config: config,
                                  staves: widget.staves,
                                  keyFifths: widget.keyFifths,
                                  beatsPerBar: widget.beatsPerBar,
                                  playheadBeat: _currentBeat,
                                  title: index == 0 ? widget.title : '',
                                  composer: index == 0 ? widget.composer : '',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              _buildTransportBar(currentMeasureNum),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopBar(
    int totalPages,
    List<ScorePage> pages,
    ScorePageConfig config,
  ) {
    return AppBar(
      backgroundColor: const Color(0xFFFAF8F5),
      elevation: 0.5,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: GameColors.ink),
        onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title.isEmpty ? 'Score View' : widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: GameColors.ink,
            ),
          ),
          if (widget.composer.isNotEmpty)
            Text(
              widget.composer,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6780)),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.print_rounded, color: GameColors.ink),
          tooltip: 'Print Score / PDF',
          onPressed: () => _printScore(pages, config),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.zoom_out, color: GameColors.ink),
          tooltip: 'Zoom Out',
          onPressed: () {
            if (_scale > 0.6) setState(() => _scale -= 0.1);
          },
        ),
        Center(
          child: Text(
            '${(_scale * 100).round()}%',
            style: const TextStyle(
              color: GameColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in, color: GameColors.ink),
          tooltip: 'Zoom In',
          onPressed: () {
            if (_scale < 1.6) setState(() => _scale += 0.1);
          },
        ),
        const SizedBox(width: 8),
        if (totalPages > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Page ${_currentPage + 1} / $totalPages',
                  style: const TextStyle(
                    color: GameColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransportBar(int currentMeasureNum) {
    final progress = widget.totalBeats > 0
        ? (_currentBeat / widget.totalBeats)
        : 0.0;
    final totalSec = (widget.totalBeats / (widget.bpm / 60.0)).round();
    final curSec = (_currentBeat / (widget.bpm / 60.0)).round();

    String fmt(int sec) {
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final s = (sec % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: GameColors.bgMid,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.replay_rounded, color: GameColors.textDim),
            tooltip: 'Restart',
            onPressed: () => _seekToBeat(0.0),
          ),
          IconButton(
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: GameColors.cyan,
              size: 44,
            ),
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlay,
          ),
          const SizedBox(width: 14),
          // Timeline scrub bar
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: GameColors.cyan,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: GameColors.cyan.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (val) => _seekToBeat(val * widget.totalBeats),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Time & Measure indicator
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fmt(curSec)} / ${fmt(totalSec)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'MEASURE $currentMeasureNum',
                style: const TextStyle(
                  color: GameColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Metronome toggle
          IconButton(
            icon: Icon(
              Icons.av_timer_rounded,
              color: _metronomeOn ? GameColors.cyan : GameColors.textDim,
            ),
            tooltip: 'Metronome',
            onPressed: () => setState(() => _metronomeOn = !_metronomeOn),
          ),
          // Speed button
          PopupMenuButton<double>(
            initialValue: _speedModifier,
            tooltip: 'Playback Speed',
            color: GameColors.panel,
            onSelected: (s) => setState(() => _speedModifier = s),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 0.5,
                child: Text('50%', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 0.75,
                child: Text('75%', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 1.0,
                child: Text('100%', style: TextStyle(color: Colors.white)),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: ShapeDecoration(
                shape: chamfer(6),
                color: GameColors.panelHi,
              ),
              child: Text(
                '${(_speedModifier * 100).round()}%',
                style: const TextStyle(
                  color: GameColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an individual sheet music page with white paper background,
/// margins, page number, and vertically stacked systems.
class ScorePageSheet extends StatelessWidget {
  const ScorePageSheet({
    super.key,
    required this.page,
    required this.config,
    required this.staves,
    required this.keyFifths,
    required this.beatsPerBar,
    required this.playheadBeat,
    this.title = '',
    this.composer = '',
  });

  final ScorePage page;
  final ScorePageConfig config;
  final Staves staves;
  final int keyFifths;
  final double beatsPerBar;
  final double playheadBeat;
  final String title;
  final String composer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: config.pageWidth,
      height: config.pageHeight,
      margin: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCF9), // Pure sightread paper
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Header: Title and Composer (Page 1)
          if (title.isNotEmpty || composer.isNotEmpty)
            Positioned(
              top: config.marginTop * 0.35,
              left: config.marginLeft,
              right: config.marginRight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    composer,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

          // Footer: Page Number
          Positioned(
            bottom: config.marginBottom * 0.4,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${page.pageIndex + 1}',
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ),
          ),

          // Systems
          Positioned.fill(
            top: title.isNotEmpty ? config.marginTop * 1.2 : config.marginTop,
            bottom: config.marginBottom,
            left: config.marginLeft,
            right: config.marginRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final system in page.systems) ...[
                  CustomPaint(
                    size: Size(config.printableWidth, config.grandStaffHeight),
                    painter: SystemStaffPainter(
                      system: system,
                      config: config,
                      staves: staves,
                      keyFifths: keyFifths,
                      beatsPerBar: beatsPerBar,
                      playheadBeat: playheadBeat,
                    ),
                  ),
                  SizedBox(height: config.systemDistance),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering a single justified system with Leland SMuFL engraving,
/// clefs, key & time signatures, measure numbers, and active playhead cursor.
class SystemStaffPainter extends CustomPainter {
  SystemStaffPainter({
    required this.system,
    required this.config,
    required this.staves,
    required this.keyFifths,
    required this.beatsPerBar,
    required this.playheadBeat,
  }) : super(repaint: musicFontReady);

  final ScoreSystem system;
  final ScorePageConfig config;
  final Staves staves;
  final int keyFifths;
  final double beatsPerBar;
  final double playheadBeat;

  static const Color ink = Color(0xFF1A1A1A);
  static const Color playheadColor = Color(
    0xFF9061F9,
  ); // Sightread purple highlight

  // Staff coordinates aligned with StaffPainter
  static const _trebleBottomStep = 30; // E4
  static const _bassTopStep = 28; // A3

  double _noteY(
    int pitch,
    bool onBass,
    double space,
    double trebleBottomY,
    double bassTopY,
  ) {
    final step = diatonicStep(pitch);
    final half = space / 2;
    return onBass
        ? bassTopY + (_bassTopStep - step) * half
        : trebleBottomY - (step - _trebleBottomStep) * half;
  }

  void _drawGlyph(
    Canvas canvas,
    String glyph,
    double size,
    Offset offset,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontFamily: 'Leland', fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(offset.dx, offset.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final staffPaint = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..strokeWidth = 1.0;

    final barlinePaint = Paint()
      ..color = ink
      ..strokeWidth = 1.1;

    final bracePaint = Paint()
      ..color = ink
      ..strokeWidth = 2.4;

    final space = config.space;
    // Standard grand staff spacing: 4 spaces treble + 3 spaces gap + 4 spaces bass
    final trebleBottomY = space * 5.0;
    final bassTopY = trebleBottomY + 3.0 * space;
    final staffTop = trebleBottomY - 4 * space;
    final staffBottom = bassTopY + 4 * space;
    final glyphSize = space * 4.0;

    // 1. Staff lines (5 treble, 5 bass)
    for (var i = 0; i < 5; i++) {
      final yT = trebleBottomY - i * space;
      canvas.drawLine(Offset(0, yT), Offset(size.width, yT), staffPaint);

      final yB = bassTopY + i * space;
      canvas.drawLine(Offset(0, yB), Offset(size.width, yB), staffPaint);
    }

    // 2. Initial system line & brace
    canvas.drawLine(Offset(0, staffTop), Offset(0, staffBottom), bracePaint);

    final x0 = -space * 1.8,
        top = staffTop,
        bot = staffBottom,
        mid = (top + bot) / 2,
        w = space * 1.3;
    final brace = Path()
      ..moveTo(x0 + w, top)
      ..cubicTo(
        x0,
        top + (mid - top) * 0.15,
        x0 + w,
        mid - (mid - top) * 0.25,
        x0,
        mid,
      )
      ..cubicTo(
        x0 + w,
        mid + (bot - mid) * 0.25,
        x0,
        bot - (bot - mid) * 0.15,
        x0 + w,
        bot,
      );
    canvas.drawPath(
      brace,
      Paint()
        ..color = ink.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = space * 0.45
        ..strokeCap = StrokeCap.round,
    );

    // 3. SMuFL Clefs (G Clef on G4, F Clef on F3)
    final clefX = space * 0.4;
    _drawGlyph(
      canvas,
      Smufl.gClef,
      glyphSize,
      Offset(clefX, trebleBottomY - space),
      ink,
    );
    _drawGlyph(
      canvas,
      Smufl.fClef,
      glyphSize,
      Offset(clefX, bassTopY + space),
      ink,
    );

    // 4. Time signature on first system
    if (system.systemIndex == 0 && beatsPerBar > 0) {
      final numGlyph = Smufl.digitGlyph(beatsPerBar.round());
      final denGlyph = Smufl.digitGlyph(4);
      final tsX = clefX + space * 3.4;
      final tsSize = space * 3.2;
      if (numGlyph != null && denGlyph != null) {
        _drawGlyph(
          canvas,
          numGlyph,
          tsSize,
          Offset(tsX, trebleBottomY - space * 3),
          ink,
        );
        _drawGlyph(
          canvas,
          denGlyph,
          tsSize,
          Offset(tsX, trebleBottomY - space * 1),
          ink,
        );

        _drawGlyph(
          canvas,
          numGlyph,
          tsSize,
          Offset(tsX, bassTopY + space * 1),
          ink,
        );
        _drawGlyph(
          canvas,
          denGlyph,
          tsSize,
          Offset(tsX, bassTopY + space * 3),
          ink,
        );
      }
    }

    // 5. Measure numbering and barlines
    final headerW = config.systemHeaderWidth;
    for (var i = 0; i < system.measures.length; i++) {
      final m = system.measures[i];
      final mLeft = headerW + system.measureXs[i];
      final x = mLeft + system.measureWidths[i];

      final measureNumText = TextPainter(
        text: TextSpan(
          text: '${m.index + 1}',
          style: TextStyle(
            color: ink.withValues(alpha: 0.7),
            fontSize: 10,
            fontFamily: 'serif',
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      measureNumText.paint(
        canvas,
        Offset(mLeft + space * 0.6, staffTop - space * 1.5),
      );

      if (x <= size.width + 1.0) {
        canvas.drawLine(
          Offset(x, staffTop),
          Offset(x, staffBottom),
          barlinePaint,
        );
      }
    }

    // 6. Real-time Playhead Cursor (Sightread-style purple highlight band)
    if (playheadBeat >= system.startBeat && playheadBeat <= system.endBeat) {
      for (var i = 0; i < system.measures.length; i++) {
        final m = system.measures[i];
        if (playheadBeat >= m.startBeat && playheadBeat <= m.endBeat) {
          final mLeft = headerW + system.measureXs[i];
          final mW = system.measureWidths[i];
          final span = m.endBeat - m.startBeat;
          final rel = span > 0 ? (playheadBeat - m.startBeat) / span : 0.0;
          final curX = mLeft + space * 1.5 + rel * (mW - space * 3.0);

          final cursorRect = Rect.fromLTRB(
            curX - space * 0.7,
            staffTop - space * 1.0,
            curX + space * 0.7,
            staffBottom + space * 1.0,
          );

          canvas.drawRRect(
            RRect.fromRectAndRadius(cursorRect, const Radius.circular(3)),
            Paint()
              ..color = playheadColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.fill,
          );
          break;
        }
      }
    }

    // 7. Render notes, stems, ledger lines with Leland SMuFL noteheads
    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final mLeft = headerW + system.measureXs[mIdx];
      final mW = system.measureWidths[mIdx];
      final mSpan = m.endBeat - m.startBeat;

      for (final note in m.notes) {
        if (note.isSpacer) continue;
        final relBeat = mSpan > 0 ? (note.beat - m.startBeat) / mSpan : 0.0;
        final nx = mLeft + space * 2.0 + relBeat * (mW - space * 4.0);

        if (note.isRest) {
          final restY = note.leftHand
              ? bassTopY + 2 * space
              : trebleBottomY - 2 * space;
          final restGlyph = note.beats >= 4
              ? Smufl.restWhole
              : note.beats >= 2
              ? Smufl.restHalf
              : note.beats >= 1
              ? Smufl.restQuarter
              : Smufl.rest8th;
          _drawGlyph(canvas, restGlyph, glyphSize, Offset(nx, restY), ink);
          continue;
        }

        final ny = _noteY(
          note.pitch,
          note.leftHand,
          space,
          trebleBottomY,
          bassTopY,
        );
        final step = diatonicStep(note.pitch);

        // Accurate ledger lines calculation:
        // On treble staff:
        // - Lines are: E4(30), G4(32), B4(34), D5(36), F5(38).
        // - Above treble: A5 is space (39), C6 is line (40). Ledgers start at step 40 for treble top.
        // - Below treble: D4 is space (29), Middle C is line (28), A3 is line (26). Ledgers start at step 28.
        // On bass staff:
        // - Lines are: G2(18), B2(20), D3(22), F3(24), A3(26).
        // - Above bass: C4 (Middle C) is line (28).
        // - Below bass: F2 is space (17), E2 is line (16), C2 is line (14).
        if (!note.leftHand) {
          if (step >= 40) {
            // Lines above treble: 40, 42, 44...
            final maxLine = (step.isEven) ? step : step - 1;
            for (var s = 40; s <= maxLine; s += 2) {
              final ly = trebleBottomY - (s - _trebleBottomStep) * (space / 2);
              canvas.drawLine(
                Offset(nx - space * 0.8, ly),
                Offset(nx + space * 1.8, ly),
                staffPaint,
              );
            }
          } else if (step <= 28) {
            // Lines below treble: 28 (Middle C), 26, 24...
            final minLine = (step.isEven) ? step : step + 1;
            for (var s = 28; s >= minLine; s -= 2) {
              final ly = trebleBottomY - (s - _trebleBottomStep) * (space / 2);
              canvas.drawLine(
                Offset(nx - space * 0.8, ly),
                Offset(nx + space * 1.8, ly),
                staffPaint,
              );
            }
          }
        } else {
          if (step >= 28) {
            // Lines above bass: 28 (Middle C)...
            final maxLine = (step.isEven) ? step : step - 1;
            for (var s = 28; s <= maxLine; s += 2) {
              final ly = bassTopY + (_bassTopStep - s) * (space / 2);
              canvas.drawLine(
                Offset(nx - space * 0.8, ly),
                Offset(nx + space * 1.8, ly),
                staffPaint,
              );
            }
          } else if (step <= 16) {
            // Lines below bass: 16, 14, 12...
            final minLine = (step.isEven) ? step : step + 1;
            for (var s = 16; s >= minLine; s -= 2) {
              final ly = bassTopY + (_bassTopStep - s) * (space / 2);
              canvas.drawLine(
                Offset(nx - space * 0.8, ly),
                Offset(nx + space * 1.8, ly),
                staffPaint,
              );
            }
          }
        }

        // SMuFL Notehead
        final headGlyph = note.beats >= 4
            ? Smufl.noteheadWhole
            : note.beats >= 2
            ? Smufl.noteheadHalf
            : Smufl.noteheadBlack;
        _drawGlyph(canvas, headGlyph, glyphSize, Offset(nx, ny), ink);

        // Stem
        if (note.beats < 4.0) {
          // Elaine Gould / MuseScore rule: RH stems point UP, LH stems point DOWN on grand staff
          final stemDown = note.isStemDown(note.leftHand, isGrandStaff: true);
          final stemX = StemLayout.stemX(
            noteheadX: nx,
            stemDown: stemDown,
            space: space,
          );
          final tipY = StemLayout.calcStemTipY(
            noteY: ny,
            stemDown: stemDown,
            space: space,
            middleLineY: note.leftHand
                ? bassTopY + 2 * space
                : trebleBottomY - 2 * space,
          );
          canvas.drawLine(
            Offset(stemX, ny),
            Offset(stemX, tipY),
            staffPaint..strokeWidth = 1.2,
          );

          // Flag for 8th / 16th notes
          if (note.beats <= 0.75) {
            final flagGlyph = stemDown ? Smufl.flag8thDown : Smufl.flag8thUp;
            _drawGlyph(canvas, flagGlyph, glyphSize, Offset(stemX, tipY), ink);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SystemStaffPainter oldDelegate) {
    return oldDelegate.system != system ||
        oldDelegate.config != config ||
        oldDelegate.keyFifths != keyFifths ||
        oldDelegate.playheadBeat != playheadBeat;
  }
}
