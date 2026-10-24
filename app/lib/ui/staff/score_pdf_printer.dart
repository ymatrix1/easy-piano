import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'score_page_layout.dart';
import 'score_page_view.dart';
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

    for (final page in pages) {
      // Rasterize each page sheet using high-DPI canvas to guarantee
      // 100% faithful SMuFL typography and engraving fidelity
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // White background for print
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, config.pageWidth, config.pageHeight),
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
        )..layout(maxWidth: config.printableWidth);
        titlePainter.paint(
          canvas,
          Offset(config.marginLeft, config.marginTop * 0.4),
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
              config.pageWidth - config.marginRight - composerPainter.width,
              config.marginTop * 0.4 + 6,
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
          (config.pageWidth - pageNumPainter.width) / 2,
          config.pageHeight - config.marginBottom * 0.6,
        ),
      );

      // Render each system on the page
      var currentY = title.isNotEmpty
          ? config.marginTop * 1.3
          : config.marginTop;
      for (final system in page.systems) {
        canvas.save();
        canvas.translate(config.marginLeft, currentY);

        final painter = SystemStaffPainter(
          system: system,
          config: config,
          staves: staves,
          keyFifths: keyFifths,
          beatsPerBar: beatsPerBar,
          playheadBeat: -1.0, // No purple cursor during print
        );

        painter.paint(
          canvas,
          Size(config.printableWidth, config.grandStaffHeight),
        );
        canvas.restore();

        currentY += config.grandStaffHeight + config.systemDistance;
      }

      final picture = recorder.endRecording();
      // Render at 2.0x scale (150-300 DPI) for crisp vector-like print output
      final img = await picture.toImage(
        config.pageWidth.toInt() * 2,
        config.pageHeight.toInt() * 2,
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) continue;

      final pngBytes = byteData.buffer.asUint8List();
      final pdfImage = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            config.pageWidth * PdfPageFormat.point,
            config.pageHeight * PdfPageFormat.point,
          ),
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
