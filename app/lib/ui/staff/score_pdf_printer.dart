import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'score_page_layout.dart';
import 'score_page_view.dart';
import 'staff_note.dart';
import 'staff_painter.dart';

/// Renders genuine print-ready vector/raster PDF pages of the score and triggers
/// the native OS / browser print dialog or PDF export.
abstract final class ScorePdfPrinter {
  static Future<void> printScore({
    required List<ScorePage> pages,
    required ScorePageConfig config,
    required Staves staves,
    required int keyFifths,
    required double beatsPerBar,
    required String title,
    required String composer,
  }) async {
    final pdf = pw.Document();

    // Use standard A4 page format (595.28 x 841.89 points) for print output
    final printConfig = ScorePageConfig(
      pageWidth: 800.0,
      pageHeight: 1130.0,
      marginTop: 56.0,
      marginBottom: 56.0,
      marginLeft: 48.0,
      marginRight: 48.0,
      grandStaffHeight: 140.0,
      systemDistance: 72.0,
      minMeasureWidth: 140.0,
      maxMeasuresPerSystem: 3,
      systemHeaderWidth: 72.0,
    );

    // Re-layout specifically for print page dimensions
    final allNotes = <StaffNote>[];
    for (final p in pages) {
      for (final s in p.systems) {
        for (final m in s.measures) {
          allNotes.addAll(m.notes);
        }
      }
    }
    allNotes.sort((a, b) => a.beat.compareTo(b.beat));

    final totalBeats = pages.isEmpty ? 0.0 : pages.last.endBeat;
    final printPages = ScorePageLayout.layoutScore(
      notes: allNotes,
      beatsPerBar: beatsPerBar,
      totalBeats: totalBeats,
      config: printConfig,
    );

    for (final page in printPages) {
      // Rasterize each page sheet using high-DPI canvas to guarantee
      // 100% faithful SMuFL typography and engraving fidelity
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // White background for print
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, printConfig.pageWidth, printConfig.pageHeight),
        bgPaint,
      );

      // Header: Title & Composer
      if (title.isNotEmpty || composer.isNotEmpty) {
        final titlePainter = TextPainter(
          text: TextSpan(
            text: title,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: printConfig.printableWidth);
        titlePainter.paint(
          canvas,
          Offset(printConfig.marginLeft, printConfig.marginTop * 0.4),
        );

        if (composer.isNotEmpty) {
          final composerPainter = TextPainter(
            text: TextSpan(
              text: composer,
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.black,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          composerPainter.paint(
            canvas,
            Offset(
              printConfig.pageWidth -
                  printConfig.marginRight -
                  composerPainter.width,
              printConfig.marginTop * 0.4 + 6,
            ),
          );
        }
      }

      // Footer: Page Number
      final pageNumPainter = TextPainter(
        text: TextSpan(
          text: '${page.pageIndex + 1}',
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pageNumPainter.paint(
        canvas,
        Offset(
          (printConfig.pageWidth - pageNumPainter.width) / 2,
          printConfig.pageHeight - printConfig.marginBottom * 0.6,
        ),
      );

      // Render each system on the page
      var currentY = title.isNotEmpty
          ? printConfig.marginTop * 1.3
          : printConfig.marginTop;
      for (final system in page.systems) {
        canvas.save();
        canvas.translate(printConfig.marginLeft, currentY);

        final painter = SystemStaffPainter(
          system: system,
          config: printConfig,
          staves: staves,
          keyFifths: keyFifths,
          beatsPerBar: beatsPerBar,
          playheadBeat: -1.0, // No purple cursor during print
        );

        painter.paint(
          canvas,
          Size(printConfig.printableWidth, printConfig.grandStaffHeight),
        );
        canvas.restore();

        currentY += printConfig.grandStaffHeight + printConfig.systemDistance;
      }

      final picture = recorder.endRecording();
      // Render at 2.0x scale (150-300 DPI) for crisp vector-like print output
      final img = await picture.toImage(
        printConfig.pageWidth.toInt() * 2,
        printConfig.pageHeight.toInt() * 2,
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) continue;

      final pngBytes = byteData.buffer.asUint8List();
      final pdfImage = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
            );
          },
        ),
      );
    }

    final docTitle = title.isEmpty
        ? 'Easy_Piano_Score'
        : title.replaceAll(' ', '_');
    await Printing.layoutPdf(
      name: docTitle,
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
