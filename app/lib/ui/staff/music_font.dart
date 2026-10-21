import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bravura (SMuFL) is 373 KB, so it is not in the pubspec font manifest,
/// which the web build fetches before the first frame. It loads in the
/// background after boot; staff painters repaint when it lands.
/// See docs/research/web-load-performance.md.
final ValueNotifier<bool> musicFontReady = ValueNotifier(false);

Future<void>? _loading;

Future<void> loadMusicFont() => _loading ??= () async {
  final loader = FontLoader('Bravura')
    ..addFont(rootBundle.load('assets/fonts/Bravura.otf'));
  await loader.load();
  musicFontReady.value = true;
}();
