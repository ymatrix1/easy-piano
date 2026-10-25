import 'package:easy_piano/ui/staff/score_pdf_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScorePdfPrinter', () {
    test('ScorePdfPrinter is defined and callable', () {
      expect(ScorePdfPrinter.printScore, isNotNull);
    });
  });
}
