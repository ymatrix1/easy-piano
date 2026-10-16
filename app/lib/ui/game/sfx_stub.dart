import 'sfx.dart';

/// Silent player for platforms without Web Audio (and for tests).
class SfxPlayer {
  void play(SfxKind kind) {}
}
