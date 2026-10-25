import 'package:easy_piano/ui/staff/score_pdf_printer.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScorePdfPrinter', () {
    test('ScorePdfPrinter is defined and callable', () {
      expect(ScorePdfPrinter.printScore, isNotNull);
    });
  });
}
