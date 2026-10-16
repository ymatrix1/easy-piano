import 'package:flutter/material.dart';

/// Fixed colours shared by both skins (see docs/specs/visual-style.md).
abstract final class GameColors {
  static const gold = Color(0xFFFFC93C);
  static const goldDark = Color(0xFFD98E04);
  static const goldLight = Color(0xFFFFE58A);
}

/// Role of a button; each skin maps it to its own face and lip colours.
enum GameTone { gold, green, blue, red, grey, wood }

/// Colours of one button tone: face (top) and lip (shadow side).
typedef ToneColors = ({Color face, Color lip});

/// Visual skin for menus. [classic] is the default; [playful] is the brighter,
/// cartoon look for kids. Chosen by the user in Settings.
class GameSkin {
  const GameSkin._({
    required this.id,
    required this.label,
    required this.playful,
    required this.bgTop,
    required this.bgBottom,
    required this.outline,
    required this.outlineWidth,
    required this.lip,
    required this.radius,
    required this.textStroke,
    required this.panelFill,
    required this.panelFrame,
    required this.panelText,
    required this.chipFill,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.trail,
    required this.resultTop,
    required this.resultBottom,
    required this.tones,
  });

  final String id;
  final String label;

  /// Cartoon extras: thick outlines, gloss, clouds, bouncy motion, ribbons.
  final bool playful;
  final Color bgTop;
  final Color bgBottom;
  final Color outline;
  final double outlineWidth;
  final double lip;
  final double radius;
  final bool textStroke;
  final Color panelFill;
  final Color panelFrame;
  final Color panelText;
  final Color chipFill;
  final Color accent;
  final Color accentLight;
  final Color accentDark;
  final Color trail;
  final Color resultTop;
  final Color resultBottom;
  final Map<GameTone, ToneColors> tones;

  ToneColors tone(GameTone t) => tones[t]!;

  /// Entrance curve: overshoot for playful, smooth for classic.
  Curve get enterCurve => playful ? Curves.easeOutBack : Curves.easeOutCubic;

  /// Calm, grown-up look: midnight blue, brass accents, thin lines.
  static const classic = GameSkin._(
    id: 'classic',
    label: 'Classic',
    playful: false,
    bgTop: Color(0xFF0E1726),
    bgBottom: Color(0xFF1B2940),
    outline: Color(0x33FFFFFF),
    outlineWidth: 1.2,
    lip: 3,
    radius: 12,
    textStroke: false,
    panelFill: Color(0xF2182335),
    panelFrame: Color(0x40D4A84B),
    panelText: Color(0xFFE6EAF2),
    chipFill: Color(0xCC0E1726),
    accent: Color(0xFFD4A84B),
    accentLight: Color(0xFFF0D38A),
    accentDark: Color(0xFF8F6A22),
    trail: Color(0x66D4A84B),
    resultTop: Color(0xFF1B2940),
    resultBottom: Color(0xFF0B121E),
    tones: {
      GameTone.gold: (face: Color(0xFFD4A84B), lip: Color(0xFF8F6A22)),
      GameTone.green: (face: Color(0xFF2FA572), lip: Color(0xFF1C6646)),
      GameTone.blue: (face: Color(0xFF3B6FC4), lip: Color(0xFF244680)),
      GameTone.red: (face: Color(0xFFC9504B), lip: Color(0xFF80302D)),
      GameTone.grey: (face: Color(0xFF4A5468), lip: Color(0xFF2C3342)),
      GameTone.wood: (face: Color(0xFF2B3850), lip: Color(0xFF172030)),
    },
  );

  /// Bright cartoon look: sky, wood, gold, thick outlines, bounce.
  static const playfulSkin = GameSkin._(
    id: 'playful',
    label: 'Playful',
    playful: true,
    bgTop: Color(0xFF3FA9F5),
    bgBottom: Color(0xFF9FE0FF),
    outline: Color(0xFF2B1A0E),
    outlineWidth: 3,
    lip: 6,
    radius: 16,
    textStroke: true,
    panelFill: Color(0xFFFFF4D6),
    panelFrame: Color(0xFFB9773C),
    panelText: Color(0xFF2B1A0E),
    chipFill: Color(0xAA1E1442),
    accent: GameColors.gold,
    accentLight: GameColors.goldLight,
    accentDark: GameColors.goldDark,
    trail: Color(0xFFF2D59A),
    resultTop: Color(0xFF3B2A7A),
    resultBottom: Color(0xFF1E1442),
    tones: {
      GameTone.gold: (face: Color(0xFFFFC93C), lip: Color(0xFFD98E04)),
      GameTone.green: (face: Color(0xFF6FD13B), lip: Color(0xFF3E9418)),
      GameTone.blue: (face: Color(0xFF46B3FF), lip: Color(0xFF1C74C9)),
      GameTone.red: (face: Color(0xFFFF6B5B), lip: Color(0xFFC0392B)),
      GameTone.grey: (face: Color(0xFFB8B8C4), lip: Color(0xFF7A7A88)),
      GameTone.wood: (face: Color(0xFFB9773C), lip: Color(0xFF7A4520)),
    },
  );

  static const all = [classic, playfulSkin];

  static GameSkin of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameSkinScope>()?.skin ??
      classic;
}

/// Current skin for the app (in memory until the settings store lands).
final skinNotifier = ValueNotifier<GameSkin>(GameSkin.classic);

/// Provides the [GameSkin] to the widget kit.
class GameSkinScope extends InheritedWidget {
  const GameSkinScope({super.key, required this.skin, required super.child});

  final GameSkin skin;

  @override
  bool updateShouldNotify(GameSkinScope old) => old.skin != skin;
}

/// True when the platform asks for reduced motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
