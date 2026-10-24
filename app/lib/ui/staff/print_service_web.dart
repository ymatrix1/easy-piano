import 'package:web/web.dart' as web;

/// Browser print trigger for web platform.
void triggerPrint() {
  web.window.print();
}
