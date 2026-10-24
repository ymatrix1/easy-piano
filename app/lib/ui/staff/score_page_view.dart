import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'score_page_layout.dart';
import 'staff_note.dart';
import 'staff_painter.dart';

/// Interactive viewer displaying multi-system, paginated sheet music
/// with MuseScore-style page breaks and system justification.
class ScorePageView extends StatefulWidget {
  const ScorePageView({
    super.key,
    required this.notes,
    required this.totalBeats,
    this.beatsPerBar = 4.0,
    this.keyFifths = 0,
    this.staves = Staves.grand,
    this.title = '',
    this.composer = '',
    this.onClose,
  });

  final List<StaffNote> notes;
  final double totalBeats;
  final double beatsPerBar;
  final int keyFifths;
  final Staves staves;
  final String title;
  final String composer;
  final VoidCallback? onClose;

  @override
  State<ScorePageView> createState() => _ScorePageViewState();
}

class _ScorePageViewState extends State<ScorePageView> {
  final _pageController = PageController();
  int _currentPage = 0;
  double _scale = 1.0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = math.max(
          600.0,
          math.min(constraints.maxWidth - 40, 900.0),
        );
        final pageHeight = math.max(800.0, constraints.maxHeight - 100);

        final config = ScorePageConfig(
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          marginTop: 64.0,
          marginBottom: 48.0,
          marginLeft: 40.0,
          marginRight: 40.0,
          grandStaffHeight: 120.0,
          systemDistance: 70.0,
          minMeasureWidth: 100.0,
        );

        final pages = ScorePageLayout.layoutScore(
          notes: widget.notes,
          beatsPerBar: widget.beatsPerBar,
          totalBeats: widget.totalBeats,
          config: config,
        );

        return Scaffold(
          backgroundColor: const Color(0xFF1E2129),
          appBar: AppBar(
            backgroundColor: const Color(0xFF15171D),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                  ),
                ),
                if (widget.composer.isNotEmpty)
                  Text(
                    widget.composer,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_out, color: Colors.white),
                tooltip: 'Zoom Out',
                onPressed: () {
                  if (_scale > 0.6) setState(() => _scale -= 0.1);
                },
              ),
              Center(
                child: Text(
                  '${(_scale * 100).round()}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in, color: Colors.white),
                tooltip: 'Zoom In',
                onPressed: () {
                  if (_scale < 1.6) setState(() => _scale += 0.1);
                },
              ),
              const SizedBox(width: 8),
              if (pages.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Page ${_currentPage + 1} / ${pages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: pages.isEmpty
              ? const Center(
                  child: Text(
                    'No score data available',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : Center(
                  child: Transform.scale(
                    scale: _scale,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
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
                              title: index == 0 ? widget.title : '',
                              composer: index == 0 ? widget.composer : '',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        );
      },
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
    this.title = '',
    this.composer = '',
  });

  final ScorePage page;
  final ScorePageConfig config;
  final Staves staves;
  final int keyFifths;
  final double beatsPerBar;
  final String title;
  final String composer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: config.pageWidth,
      height: config.pageHeight,
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCF9), // Ivory paper tint
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Header: Title and Composer (Page 1)
          if (title.isNotEmpty || composer.isNotEmpty)
            Positioned(
              top: config.marginTop * 0.4,
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
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    composer,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 14,
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

/// Custom painter rendering a single justified system (treble + bass staves,
/// measure barlines, clefs, and notes).
class SystemStaffPainter extends CustomPainter {
  SystemStaffPainter({
    required this.system,
    required this.config,
    required this.staves,
    required this.keyFifths,
    required this.beatsPerBar,
  });

  final ScoreSystem system;
  final ScorePageConfig config;
  final Staves staves;
  final int keyFifths;
  final double beatsPerBar;

  static const Color ink = Color(0xFF1A1A1A);

  @override
  void paint(Canvas canvas, Size size) {
    final staffPaint = Paint()
      ..color = ink.withValues(alpha: 0.85)
      ..strokeWidth = 1.0;

    final barlinePaint = Paint()
      ..color = ink
      ..strokeWidth = 1.2;

    final bracePaint = Paint()
      ..color = ink
      ..strokeWidth = 2.5;

    final space = config.space;
    final trebleTop = space * 1.5;
    final bassTop = trebleTop + 4 * space + space * 3.5;

    // Draw staff lines (5 for treble, 5 for bass)
    for (var i = 0; i < 5; i++) {
      final yT = trebleTop + i * space;
      canvas.drawLine(Offset(0, yT), Offset(size.width, yT), staffPaint);

      final yB = bassTop + i * space;
      canvas.drawLine(Offset(0, yB), Offset(size.width, yB), staffPaint);
    }

    // Grand staff brace / vertical connector at start
    final grandBottom = bassTop + 4 * space;
    canvas.drawLine(Offset(0, trebleTop), Offset(0, grandBottom), bracePaint);

    // Barlines for each measure in the system
    final headerW = config.systemHeaderWidth;
    for (var i = 0; i < system.measures.length; i++) {
      final x = headerW + system.measureXs[i] + system.measureWidths[i];
      // Only draw within system bounds
      if (x <= size.width + 1.0) {
        canvas.drawLine(
          Offset(x, trebleTop),
          Offset(x, grandBottom),
          barlinePaint,
        );
      }
    }

    // Paint notes in each measure
    final notePaint = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;

    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final mLeft = headerW + system.measureXs[mIdx];
      final mW = system.measureWidths[mIdx];

      for (final note in m.notes) {
        // Proportionate placement inside measure
        final relBeat = (note.beat - m.startBeat) / (m.endBeat - m.startBeat);
        final nx = mLeft + space * 2.0 + relBeat * (mW - space * 4.0);

        // Approximate vertical placement
        final staffBaseY = note.leftHand ? bassTop : trebleTop;
        final ny = staffBaseY + (note.leftHand ? space * 2.0 : space * 2.0);

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(nx, ny),
            width: space * 1.3,
            height: space * 0.95,
          ),
          notePaint,
        );

        // Draw note stem
        canvas.drawLine(
          Offset(nx + space * 0.6, ny),
          Offset(nx + space * 0.6, ny - space * 3.2),
          staffPaint..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SystemStaffPainter oldDelegate) {
    return oldDelegate.system != system ||
        oldDelegate.config != config ||
        oldDelegate.keyFifths != keyFifths;
  }
}
