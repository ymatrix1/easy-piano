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

    const dpiScale = 2.0;
    final imgWidth = (config.pageWidth * dpiScale).round();
    final imgHeight = (config.pageHeight * dpiScale).round();

    for (final page in pages) {
      // Rasterize each page sheet using high-DPI canvas to guarantee
      // 100% faithful SMuFL typography and engraving fidelity
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(dpiScale, dpiScale);

      // White background for print
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, config.pageWidth, config.pageHeight),
        bgPaint,
      );

      // Header: Title & Composer (Page 1)
      if (page.pageIndex == 0 && (title.isNotEmpty || composer.isNotEmpty)) {
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
        )..layout(maxWidth: config.printableWidth * 0.7);
        titlePainter.paint(canvas, Offset(config.marginLeft, 24.0));

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
              30.0,
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

      // Render each system on the page (with dynamic vertical justification matching on-screen view)
      final hasHeader =
          page.pageIndex == 0 && (title.isNotEmpty || composer.isNotEmpty);
      final topY = hasHeader ? 88.0 : config.marginTop;
      final availableH = config.pageHeight - topY - config.marginBottom;
      final totalStaffsH = page.systems.length * config.grandStaffHeight;
      final dynamicGap = page.systems.length > 1
          ? ((availableH - totalStaffsH) / (page.systems.length - 1)).clamp(
              config.systemDistance,
              config.systemDistance * 1.4,
            )
          : config.systemDistance;

      var currentY = topY;
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

        currentY += config.grandStaffHeight + dynamicGap;
      }

      final picture = recorder.endRecording();
      // Render at 2.0x scale (150-300 DPI) for crisp vector-like print output
      final img = await picture.toImage(imgWidth, imgHeight);
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
