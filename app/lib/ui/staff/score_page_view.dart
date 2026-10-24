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
  final _scrollController = ScrollController();
  late final Ticker _ticker;

  int _currentPage = 0;
  double _scale = 1.0;
  bool _isPlaying = false;
  double _currentBeat = 0.0;
  double _speedModifier = 1.0;
  bool _metronomeOn = false;

  double _lastTickMs = 0.0;
  double _lastMetronomeBeat = -1.0;
  int _lastActiveSysKey = -1;

  ScorePageConfig? _lastConfig;
  List<ScorePage> _lastPages = const [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    pianoSynth.stopAll();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _lastConfig == null) return;
    final pageH = (_lastConfig!.pageHeight + 24.0) * _scale;
    if (pageH <= 0) return;
    final page = (_scrollController.offset / pageH)
        .floor()
        .clamp(0, math.max(0, _lastPages.length - 1))
        .toInt();
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
  }

  void _scrollToPage(int targetPage) {
    if (!_scrollController.hasClients || _lastConfig == null) return;
    final pageH = (_lastConfig!.pageHeight + 24.0) * _scale;
    final targetOffset = (targetPage * pageH).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
    setState(() => _currentPage = targetPage);
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

    // Auto-scroll vertically following playhead downwards across systems and pages (MuseScore style)
    if (_lastPages.isNotEmpty &&
        _lastConfig != null &&
        _scrollController.hasClients) {
      final config = _lastConfig!;
      for (var p = 0; p < _lastPages.length; p++) {
        final page = _lastPages[p];
        if (nextBeat >= page.startBeat && nextBeat <= page.endBeat) {
          for (var s = 0; s < page.systems.length; s++) {
            final sys = page.systems[s];
            if (nextBeat >= sys.startBeat && nextBeat <= sys.endBeat) {
              final sysKey = p * 1000 + s;
              if (sysKey != _lastActiveSysKey) {
                _lastActiveSysKey = sysKey;
                final pageH = (config.pageHeight + 24.0) * _scale;
                final sysY =
                    (p == 0 && widget.title.isNotEmpty
                        ? config.marginTop * 1.2
                        : config.marginTop) +
                    s * (config.grandStaffHeight + config.systemDistance);
                final targetScroll = (p * pageH + sysY * _scale - 100.0).clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                );
                _scrollController.animateTo(
                  targetScroll,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                );
              }
              break;
            }
          }
          break;
        }
      }
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
          _lastActiveSysKey = -1;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0.0);
          }
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
      _lastActiveSysKey = -1;
    });

    if (_lastPages.isNotEmpty &&
        _lastConfig != null &&
        _scrollController.hasClients) {
      if (_currentBeat <= 0.05) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }
      final config = _lastConfig!;
      for (var p = 0; p < _lastPages.length; p++) {
        final page = _lastPages[p];
        if (_currentBeat >= page.startBeat && _currentBeat <= page.endBeat) {
          for (var s = 0; s < page.systems.length; s++) {
            final sys = page.systems[s];
            if (_currentBeat >= sys.startBeat && _currentBeat <= sys.endBeat) {
              final pageH = (config.pageHeight + 24.0) * _scale;
              final sysY =
                  (p == 0 && widget.title.isNotEmpty
                      ? config.marginTop * 1.2
                      : config.marginTop) +
                  s * (config.grandStaffHeight + config.systemDistance);
              final targetScroll = (p * pageH + sysY * _scale - 100.0).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.animateTo(
                targetScroll,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
              break;
            }
          }
          break;
        }
      }
    }
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

        _lastConfig = config;
        _lastPages = pages;

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
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        itemCount: pages.length,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: SizedBox(
                                width: config.pageWidth * _scale,
                                height: config.pageHeight * _scale,
                                child: FittedBox(
                                  fit: BoxFit.contain,
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
                              ),
                            ),
                          );
                        },
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
        const SizedBox(width: 4),
        if (totalPages > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: GameColors.ink,
                    ),
                    tooltip: 'Previous Page',
                    onPressed: _currentPage > 0
                        ? () => _scrollToPage(_currentPage - 1)
                        : null,
                  ),
                  Container(
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
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: GameColors.ink,
                    ),
                    tooltip: 'Next Page',
                    onPressed: _currentPage < totalPages - 1
                        ? () => _scrollToPage(_currentPage + 1)
                        : null,
                  ),
                ],
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
    final hasHeader =
        page.pageIndex == 0 && (title.isNotEmpty || composer.isNotEmpty);

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
          if (hasHeader)
            Positioned(
              top: 24.0,
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
            top: hasHeader ? 88.0 : config.marginTop,
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

  static const _stepOf = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];

  static int diatonicStep(int pitch) =>
      (pitch ~/ 12 - 1) * 7 + _stepOf[pitch % 12];

  static final _trebleBottomStep = diatonicStep(64); // E4 = 30
  static final _bassTopStep = diatonicStep(57); // A3 = 26

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
    Offset origin,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontFamily: 'Leland', fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(canvas, Offset(origin.dx, origin.dy - baseline));
  }

  void _drawLedgerLines({
    required Canvas canvas,
    required double nx,
    required int step,
    required bool onBass,
    required double space,
    required double trebleBottomY,
    required double bassTopY,
    required Paint staffPaint,
  }) {
    final half = space / 2;
    final left = nx - space * 0.45;
    final right = nx + space * 1.75;

    void drawLine(double ly) {
      canvas.drawLine(Offset(left, ly), Offset(right, ly), staffPaint);
    }

    if (!onBass && step < _trebleBottomStep) {
      // Below treble staff: C4 (Middle C), A3, etc.
      for (var s = _trebleBottomStep - 2; s >= step; s -= 2) {
        final ly = trebleBottomY + (_trebleBottomStep - s) * half;
        drawLine(ly);
      }
    }
    if (!onBass && step > _trebleBottomStep + 8) {
      // Above treble staff: A5, C6, etc.
      for (var s = _trebleBottomStep + 10; s <= step; s += 2) {
        final ly = trebleBottomY - (s - _trebleBottomStep) * half;
        drawLine(ly);
      }
    }
    if (onBass && step > _bassTopStep) {
      // Above bass staff: C4 (Middle C), E4, etc.
      for (var s = _bassTopStep + 2; s <= step; s += 2) {
        final ly = bassTopY - (s - _bassTopStep) * half;
        drawLine(ly);
      }
    }
    if (onBass && step < _bassTopStep - 8) {
      // Below bass staff: E2, C2, etc.
      for (var s = _bassTopStep - 10; s >= step; s -= 2) {
        final ly = bassTopY + (_bassTopStep - s) * half;
        drawLine(ly);
      }
    }
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
    final headerW = config.systemHeaderWidth;
    final trebleBottomY = space * 5.0;
    final bassTopY = trebleBottomY + 3.0 * space;
    final staffTop = trebleBottomY - 4 * space;
    final staffBottom = bassTopY + 4 * space;
    final glyphSize = space * 4.0;

    // 1. Staff lines (5 treble, 5 bass) spanning justified system width
    final systemW =
        headerW +
        (system.measureXs.isNotEmpty
            ? (system.measureXs.last + system.measureWidths.last)
            : size.width);

    for (var i = 0; i < 5; i++) {
      final yT = trebleBottomY - i * space;
      canvas.drawLine(Offset(0, yT), Offset(systemW, yT), staffPaint);

      final yB = bassTopY + i * space;
      canvas.drawLine(Offset(0, yB), Offset(systemW, yB), staffPaint);
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

    // 4. Key signature & Time signature on first system
    var headerCurX = clefX + space * 3.4;
    if (keyFifths != 0) {
      KeySignatureLayout.drawKeySignature(
        canvas: canvas,
        startX: headerCurX,
        fifths: keyFifths,
        onBass: false,
        space: space,
        trebleBottomY: trebleBottomY,
        bassTopY: bassTopY,
        color: ink,
        drawGlyph: _drawGlyph,
      );
      KeySignatureLayout.drawKeySignature(
        canvas: canvas,
        startX: headerCurX,
        fifths: keyFifths,
        onBass: true,
        space: space,
        trebleBottomY: trebleBottomY,
        bassTopY: bassTopY,
        color: ink,
        drawGlyph: _drawGlyph,
      );
      headerCurX += KeySignatureLayout.width(keyFifths, space);
    }

    if (system.systemIndex == 0 && beatsPerBar > 0) {
      final numGlyph = Smufl.digitGlyph(beatsPerBar.round());
      final denGlyph = Smufl.digitGlyph(4);
      final tsSize = space * 3.2;
      if (numGlyph != null && denGlyph != null) {
        _drawGlyph(
          canvas,
          numGlyph,
          tsSize,
          Offset(headerCurX, trebleBottomY - space * 3),
          ink,
        );
        _drawGlyph(
          canvas,
          denGlyph,
          tsSize,
          Offset(headerCurX, trebleBottomY - space * 1),
          ink,
        );
        _drawGlyph(
          canvas,
          numGlyph,
          tsSize,
          Offset(headerCurX, bassTopY + space * 1),
          ink,
        );
        _drawGlyph(
          canvas,
          denGlyph,
          tsSize,
          Offset(headerCurX, bassTopY + space * 3),
          ink,
        );
      }
    }

    // 5. Measure numbering and barlines
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

      // Right barline (last barline of the piece drawn with standard double end barline)
      if (x <= size.width + 2.0) {
        if (i == system.measures.length - 1 && system.isLastSystem) {
          canvas.drawLine(
            Offset(x - space * 0.4, staffTop),
            Offset(x - space * 0.4, staffBottom),
            barlinePaint,
          );
          canvas.drawLine(
            Offset(x, staffTop),
            Offset(x, staffBottom),
            Paint()
              ..color = ink
              ..strokeWidth = 2.8,
          );
        } else {
          canvas.drawLine(
            Offset(x, staffTop),
            Offset(x, staffBottom),
            barlinePaint,
          );
        }
      }
    }

    // Flatten all notes in system for cross-measure beaming and accidentals
    final allSysNotes = <StaffNote>[];
    final noteXsMap = <int, double>{};
    final beatPoints = <({double beat, double x})>[];

    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final mLeft = headerW + system.measureXs[mIdx];
      final mW = system.measureWidths[mIdx];
      final mSpan = math.max(0.001, m.endBeat - m.startBeat);
      final padLeft = space * 1.8;
      final padRight = space * 1.5;
      final usableW = math.max(10.0, mW - padLeft - padRight);

      // Map unique beats in this measure
      final mBeats = <double>{};
      for (final n in m.notes) {
        if (!n.isSpacer) mBeats.add(n.beat);
      }
      if (mBeats.isEmpty) {
        mBeats.add(m.startBeat);
      }
      final sortedBeats = mBeats.toList()..sort();
      for (final b in sortedBeats) {
        final rel = ((b - m.startBeat) / mSpan).clamp(0.0, 1.0);
        final x = mLeft + padLeft + rel * usableW;
        beatPoints.add((beat: b, x: x));
      }

      for (final note in m.notes) {
        if (note.isSpacer) continue;
        final relBeat = ((note.beat - m.startBeat) / mSpan).clamp(0.0, 1.0);
        final nx = mLeft + padLeft + relBeat * usableW;
        final globalIdx = allSysNotes.length;
        allSysNotes.add(note);
        noteXsMap[globalIdx] = nx;
      }
    }

    // Boundary beat points for smooth interpolation across lines and barlines
    if (beatPoints.isNotEmpty) {
      if (beatPoints.first.beat > system.startBeat) {
        beatPoints.insert(0, (
          beat: system.startBeat,
          x: headerW + space * 1.5,
        ));
      }
      if (beatPoints.last.beat < system.endBeat) {
        beatPoints.add((
          beat: system.endBeat,
          x:
              headerW +
              (system.measureXs.last + system.measureWidths.last) -
              space * 1.5,
        ));
      }
    }

    // 6. Real-time Playhead Cursor (Sightread-style smooth gliding highlight band)
    if (playheadBeat >= system.startBeat &&
        playheadBeat <= system.endBeat &&
        beatPoints.length >= 2) {
      double curX = beatPoints.first.x;
      for (var k = 0; k < beatPoints.length - 1; k++) {
        final p0 = beatPoints[k];
        final p1 = beatPoints[k + 1];
        if (playheadBeat >= p0.beat && playheadBeat <= p1.beat) {
          final span = p1.beat - p0.beat;
          final t = span > 0 ? (playheadBeat - p0.beat) / span : 0.0;
          curX = p0.x + t * (p1.x - p0.x);
          break;
        }
      }

      final cursorRect = Rect.fromLTRB(
        curX - space * 0.7,
        staffTop - space * 1.0,
        curX + space * 0.7,
        staffBottom + space * 1.0,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(cursorRect, const Radius.circular(3)),
        Paint()
          ..color = playheadColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
    }

    // 7. Accidentals computation matching Mode 1 StaffPainter
    final noteAccidentals = StaffPainter.computeAccidentals(
      notes: allSysNotes,
      keyFifths: keyFifths,
      beatsPerBar: beatsPerBar,
      onBass: (n) => n.leftHand,
    );

    // 8. Beaming layout matching Mode 1 StaffPainter
    final beamGroups = BeamLayout.computeBeamGroups(
      notes: allSysNotes,
      first: 0,
      lastBeat: allSysNotes.isEmpty ? 0.0 : allSysNotes.last.beat + 4.0,
      onBass: (n) => n.leftHand,
      noteY: (pitch, onB) => _noteY(pitch, onB, space, trebleBottomY, bassTopY),
      noteXs: noteXsMap,
      space: space,
      beatsPerBar: beatsPerBar,
      isGrandStaff: true,
    );

    final beamedIndices = <int>{};
    for (final g in beamGroups) {
      beamedIndices.addAll(g.allIndices);
    }

    // Render beams
    for (final g in beamGroups) {
      BeamLayout.drawBeamGroup(
        canvas: canvas,
        group: g,
        notes: allSysNotes,
        noteY: (pitch, onB) =>
            _noteY(pitch, onB, space, trebleBottomY, bassTopY),
        onBass: (n) => n.leftHand,
        space: space,
        defaultColor: ink,
        colorOf: null,
      );
    }

    // 9. Render notes, rests, ledger lines, noteheads, accidentals, and un-beamed stems
    for (var i = 0; i < allSysNotes.length; i++) {
      final note = allSysNotes[i];
      final nx = noteXsMap[i] ?? 0.0;

      if (note.isRest) {
        final restY = note.leftHand
            ? (note.beats >= 4
                  ? bassTopY + 2 * space
                  : (note.beats >= 2
                        ? bassTopY + 3 * space
                        : bassTopY + 2 * space))
            : (note.beats >= 4
                  ? trebleBottomY - 3 * space
                  : (note.beats >= 2
                        ? trebleBottomY - 2 * space
                        : trebleBottomY - 2 * space));
        final restGlyph = note.beats >= 4
            ? Smufl.restWhole
            : note.beats >= 2
            ? Smufl.restHalf
            : note.beats >= 1
            ? Smufl.restQuarter
            : note.beats >= 0.5
            ? Smufl.rest8th
            : Smufl.rest16th;
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

      // Ledger lines (precise formula from StaffPainter)
      _drawLedgerLines(
        canvas: canvas,
        nx: nx,
        step: step,
        onBass: note.leftHand,
        space: space,
        trebleBottomY: trebleBottomY,
        bassTopY: bassTopY,
        staffPaint: staffPaint,
      );

      // Accidental
      final acc = noteAccidentals[i];
      if (acc != null) {
        final accGlyph = switch (acc) {
          AccidentalType.sharp => Smufl.accidentalSharp,
          AccidentalType.flat => Smufl.accidentalFlat,
          AccidentalType.natural => Smufl.accidentalNatural,
        };
        _drawGlyph(
          canvas,
          accGlyph,
          glyphSize,
          Offset(nx - space * 1.3, ny),
          ink,
        );
      }

      // Notehead
      final headGlyph = note.beats >= 4
          ? Smufl.noteheadWhole
          : note.beats >= 2
          ? Smufl.noteheadHalf
          : Smufl.noteheadBlack;
      _drawGlyph(canvas, headGlyph, glyphSize, Offset(nx, ny), ink);

      // Augmentation dot
      if ((note.beats - 1.5).abs() < 1e-4 ||
          (note.beats - 3.0).abs() < 1e-4 ||
          (note.beats - 0.75).abs() < 1e-4 ||
          (note.beats - 0.375).abs() < 1e-4) {
        final half = space / 2;
        final dy = step.isEven ? -half : 0.0;
        canvas.drawCircle(
          Offset(nx + (note.beats >= 4 ? 1.6 : 1.4) * space, ny + dy),
          space * 0.18,
          Paint()..color = ink,
        );
      }

      // Stem and flag (for notes NOT part of a beam group)
      if (!beamedIndices.contains(i) && note.beats < 4.0) {
        final isRH = !note.leftHand;
        final stemDown = isRH
            ? step >= (_trebleBottomStep + 4)
            : step >= (_bassTopStep - 4);
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

        if (note.beats <= 0.75) {
          final flagGlyph = note.beats <= 0.25
              ? (stemDown ? Smufl.flag16thDown : Smufl.flag16thUp)
              : (stemDown ? Smufl.flag8thDown : Smufl.flag8thUp);
          _drawGlyph(canvas, flagGlyph, glyphSize, Offset(stemX, tipY), ink);
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
