import 'package:flutter/foundation.dart';

import 'sfx_stub.dart' if (dart.library.js_interop) 'sfx_web.dart' as impl;

/// Menu sound effects. All sounds are synthesised at runtime (no audio
/// files), so they are license-clean and weigh nothing. Web uses Web Audio;
/// other platforms are silent until the native audio engine lands.
/// See docs/specs/visual-style.md.
enum SfxKind {
  hover,
  tap,
  confirm,
  open,
  close,
  tab,
  locked,
  star1,
  star2,
  star3,
  win,
  lose,
}

abstract final class Sfx {
  /// User setting (Profile → Sound effects); in memory for now.
  static final muted = ValueNotifier<bool>(false);

  static final impl.SfxPlayer _player = impl.SfxPlayer();

  static void play(SfxKind kind) {
    if (muted.value) return;
    try {
      _player.play(kind);
    } catch (_) {
      // Sound is decoration; never let it break the UI.
    }
  }

  /// Star chime for the [i]-th star (0–2).
  static void star(int i) =>
      play(const [SfxKind.star1, SfxKind.star2, SfxKind.star3][i.clamp(0, 2)]);
}
