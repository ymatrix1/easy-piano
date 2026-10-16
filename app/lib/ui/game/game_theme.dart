import 'package:flutter/material.dart';

/// Game menu palette (ours; see docs/specs/visual-style.md).
abstract final class GameColors {
  static const skyTop = Color(0xFF3FA9F5);
  static const skyBottom = Color(0xFF9FE0FF);
  static const grass = Color(0xFF7BD148);
  static const grassDark = Color(0xFF4E9A2A);
  static const gold = Color(0xFFFFC93C);
  static const goldDark = Color(0xFFD98E04);
  static const goldLight = Color(0xFFFFE58A);
  static const green = Color(0xFF6FD13B);
  static const greenDark = Color(0xFF3E9418);
  static const blue = Color(0xFF46B3FF);
  static const blueDark = Color(0xFF1C74C9);
  static const red = Color(0xFFFF6B5B);
  static const redDark = Color(0xFFC0392B);
  static const grey = Color(0xFFB8B8C4);
  static const greyDark = Color(0xFF7A7A88);
  static const wood = Color(0xFFB9773C);
  static const woodDark = Color(0xFF7A4520);
  static const parchment = Color(0xFFFFF4D6);
  static const outline = Color(0xFF2B1A0E);
  static const night = Color(0xFF3B2A7A);
  static const nightDeep = Color(0xFF1E1442);
}

/// Face colour and lip (shadow side) colour of a chunky button.
enum GameTone {
  gold(GameColors.gold, GameColors.goldDark),
  green(GameColors.green, GameColors.greenDark),
  blue(GameColors.blue, GameColors.blueDark),
  red(GameColors.red, GameColors.redDark),
  grey(GameColors.grey, GameColors.greyDark),
  wood(GameColors.wood, GameColors.woodDark);

  const GameTone(this.face, this.lip);
  final Color face;
  final Color lip;
}

/// True when the platform asks for reduced motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
