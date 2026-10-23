import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SMuFL music font loader (Leland with Bravura fallback).
/// Leland is the clean engraving font from MuseScore (86 KB), loaded in the
/// background after boot; staff painters repaint when it lands.
/// See docs/research/web-load-performance.md.
final ValueNotifier<bool> musicFontReady = ValueNotifier(false);

Future<void>? _loading;

Future<void> loadMusicFont() => _loading ??= () async {
  final lelandLoader = FontLoader('Leland')
    ..addFont(rootBundle.load('assets/fonts/Leland.otf'));
  final bravuraLoader = FontLoader('Bravura')
    ..addFont(rootBundle.load('assets/fonts/Bravura.otf'));
  await Future.wait([lelandLoader.load(), bravuraLoader.load()]);
  musicFontReady.value = true;
}();
