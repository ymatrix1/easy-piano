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
    required List<StaffNote> notes,
    required double totalBeats,
    required double beatsPerBar,
    required Staves staves,
    required int keyFifths,
    required String title,
    required String composer,
  }) async {
    final docTitle = title.isEmpty
        ? 'Easy_Piano_Score'
        : title.replaceAll(' ', '_');

    await Printing.layoutPdf(
      name: docTitle,
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();

        // 1. Calculate print dimensions preserving the EXACT aspect ratio of the paper
        final paperAspectRatio = format.height / format.width;
        const printPageWidth = 800.0;
        final printPageHeight = printPageWidth * paperAspectRatio;

        final printConfig = ScorePageConfig(
          pageWidth: printPageWidth,
          pageHeight: printPageHeight,
          marginTop: 48.0,
          marginBottom: 44.0,
          marginLeft: 40.0,
          marginRight: 40.0,
          grandStaffHeight: 135.0,
          systemDistance: 52.0,
          minMeasureWidth: 105.0,
          systemHeaderWidth: 64.0,
          maxMeasuresPerSystem: 4,
          minMeasuresPerSystem: 2,
        );

        // 2. Break systems and paginate specifically for print paper dimensions
        final measures = ScorePageLayout.buildMeasures(
          notes: notes,
          beatsPerBar: beatsPerBar,
          totalBeats: totalBeats,
          space: printConfig.space,
          minMeasureWidth: printConfig.minMeasureWidth,
        );

        final systems = ScorePageLayout.breakSystems(
          measures: measures,
          config: printConfig,
        );

        final pages = ScorePageLayout.paginate(
          systems: systems,
          config: printConfig,
        );

        // 3. Render each print page at 2.5x high DPI (equivalent to 300 DPI on physical paper)
        const dpiScale = 2.5;
        final imgWidth = (printPageWidth * dpiScale).round();
        final imgHeight = (printPageHeight * dpiScale).round();

        for (final page in pages) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.scale(dpiScale, dpiScale);

          // Pure white background for print
          final bgPaint = Paint()..color = Colors.white;
          canvas.drawRect(
            Rect.fromLTWH(0, 0, printPageWidth, printPageHeight),
            bgPaint,
          );

          // Header on Page 1: Title & Composer
          if (page.pageIndex == 0 &&
              (title.isNotEmpty || composer.isNotEmpty)) {
            final titlePainter = TextPainter(
              text: TextSpan(
                text: title,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: printConfig.printableWidth * 0.7);
            titlePainter.paint(canvas, Offset(printConfig.marginLeft, 28.0));

            if (composer.isNotEmpty) {
              final composerPainter = TextPainter(
                text: TextSpan(
                  text: composer,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 14,
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
                  36.0,
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
              printConfig.pageHeight - printConfig.marginBottom * 0.65,
            ),
          );

          // Render systems with vertical justification
          final hasHeader =
              page.pageIndex == 0 && (title.isNotEmpty || composer.isNotEmpty);
          final topY = hasHeader ? 96.0 : printConfig.marginTop;
          final availableH =
              printConfig.pageHeight - topY - printConfig.marginBottom;
          final totalStaffsH =
              page.systems.length * printConfig.grandStaffHeight;
          final dynamicGap = page.systems.length > 1
              ? ((availableH - totalStaffsH) / (page.systems.length - 1)).clamp(
                  printConfig.systemDistance,
                  printConfig.systemDistance * 1.35,
                )
              : printConfig.systemDistance;

          var currentY = topY;
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

            currentY += printConfig.grandStaffHeight + dynamicGap;
          }

          final picture = recorder.endRecording();
          final img = await picture.toImage(imgWidth, imgHeight);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          if (byteData == null) continue;

          final pngBytes = byteData.buffer.asUint8List();
          final pdfImage = pw.MemoryImage(pngBytes);

          pdf.addPage(
            pw.Page(
              pageFormat: format,
              margin: pw.EdgeInsets.zero,
              build: (context) {
                return pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                );
              },
            ),
          );
        }

        return pdf.save();
      },
    );
  }
}
