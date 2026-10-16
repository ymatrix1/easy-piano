import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_theme.dart';

/// Heavy display text with a dark outline and drop shadow.
class GameText extends StatelessWidget {
  const GameText(
    this.text, {
    super.key,
    this.size = 24,
    this.color = Colors.white,
    this.stroke,
    this.align = TextAlign.center,
  });

  final String text;
  final double size;
  final Color color;

  /// Outline width; defaults to about 1/8 of the font size.
  final double? stroke;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final w = stroke ?? (size / 8).clamp(2.0, 5.0);
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.5,
      height: 1.1,
    );
    return Stack(
      children: [
        Text(
          text,
          textAlign: align,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 2
              ..strokeJoin = StrokeJoin.round
              ..color = GameColors.outline,
            shadows: [
              Shadow(
                color: Colors.black38,
                offset: Offset(0, w * 0.9),
                blurRadius: 0,
              ),
            ],
          ),
        ),
        Text(
          text,
          textAlign: align,
          style: base.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Press feedback shared by the chunky buttons: the face sinks onto its lip
/// and squashes, then springs back.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(double press) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() => _c.forward();
  void _up() => _c.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _down() : null,
        onTapUp: enabled ? (_) => _up() : null,
        onTapCancel: enabled ? _up : null,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // Springy release: elastic curve on the way back.
            final t = _c.status == AnimationStatus.reverse
                ? Curves.elasticIn.transform(_c.value)
                : _c.value;
            return widget.builder(t);
          },
        ),
      ),
    );
  }
}

const _lip = 6.0;

BoxDecoration _faceDecoration(
  GameTone tone,
  BorderRadius radius, {
  BoxShape shape = BoxShape.rectangle,
}) {
  return BoxDecoration(
    shape: shape,
    borderRadius: shape == BoxShape.circle ? null : radius,
    border: Border.all(color: GameColors.outline, width: 3),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(tone.face, Colors.white, 0.35)!, tone.face],
    ),
  );
}

/// Chunky beveled button with an outlined label.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = GameTone.gold,
    this.icon,
    this.fontSize = 22,
    this.minWidth = 160,
  });

  final String label;
  final VoidCallback? onTap;
  final GameTone tone;
  final IconData? icon;
  final double fontSize;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final t = onTap == null ? GameTone.grey : tone;
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: _Pressable(
        onTap: onTap,
        builder: (p) => Transform.scale(
          scale: 1 - 0.06 * p,
          child: Padding(
            padding: EdgeInsets.only(top: _lip * p),
            child: Container(
              constraints: BoxConstraints(minWidth: minWidth),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: GameColors.outline,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              padding: EdgeInsets.only(bottom: _lip * (1 - p)),
              child: Container(
                decoration: BoxDecoration(borderRadius: radius, color: t.lip),
                padding: const EdgeInsets.only(bottom: 3),
                child: DecoratedBox(
                  decoration: _faceDecoration(t, radius),
                  child: _Gloss(
                    radius: radius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            _OutlinedIcon(icon!, size: fontSize * 1.2),
                            const SizedBox(width: 8),
                          ],
                          GameText(label, size: fontSize),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon-only version of [GameButton].
class GameRoundButton extends StatelessWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tone = GameTone.blue,
    this.size = 56,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final GameTone tone;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = onTap == null ? GameTone.grey : tone;
    final button = Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: _Pressable(
        onTap: onTap,
        builder: (p) => SizedBox(
          width: size,
          height: size + _lip,
          child: Transform.scale(
            scale: 1 - 0.08 * p,
            child: Stack(
              children: [
                // Lip.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: size,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.lip,
                      border: Border.all(color: GameColors.outline, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                // Face.
                Positioned(
                  left: 0,
                  right: 0,
                  top: _lip * p,
                  height: size,
                  child: DecoratedBox(
                    decoration: _faceDecoration(
                      t,
                      BorderRadius.zero,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: _Gloss(
                        radius: BorderRadius.circular(size),
                        child: Center(
                          child: _OutlinedIcon(icon, size: size * 0.56),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// White top-half shine over a button face.
class _Gloss extends StatelessWidget {
  const _Gloss({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 6,
          right: 6,
          top: 3,
          child: FractionallySizedBox(
            widthFactor: 1,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Icon with a dark outline (drawn as offset copies) and drop shadow.
class _OutlinedIcon extends StatelessWidget {
  const _OutlinedIcon(this.icon, {required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final o = (size / 14).clamp(1.5, 3.0);
    return SizedBox(
      width: size + o * 2,
      height: size + o * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final d in const [
            Offset(-1, 0),
            Offset(1, 0),
            Offset(0, -1),
            Offset(0, 1),
            Offset(-0.7, -0.7),
            Offset(0.7, 0.7),
            Offset(-0.7, 0.7),
            Offset(0.7, -0.7),
            Offset(0, 1.8),
          ])
            Transform.translate(
              offset: d * o,
              child: Icon(icon, size: size, color: GameColors.outline),
            ),
          Icon(icon, size: size, color: Colors.white),
        ],
      ),
    );
  }
}

/// Parchment card in a wood frame, with an optional ribbon title.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.title,
    this.maxWidth = 560,
  });

  final Widget child;
  final String? title;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: GameColors.outline,
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GameColors.wood, GameColors.woodDark],
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: GameColors.parchment,
            border: Border.all(color: GameColors.outline, width: 2.5),
          ),
          padding: EdgeInsets.fromLTRB(24, title == null ? 22 : 40, 24, 22),
          child: child,
        ),
      ),
    );
    if (title == null) return panel;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: 26), child: panel),
        GameRibbon(title!),
      ],
    );
  }
}

/// Banner-style title plaque with folded tails.
class GameRibbon extends StatelessWidget {
  const GameRibbon(
    this.text, {
    super.key,
    this.tone = GameTone.red,
    this.fontSize = 26,
  });

  final String text;
  final GameTone tone;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonPainter(tone),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 10),
        child: GameText(text, size: fontSize),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.tone);

  final GameTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outline = Paint()
      ..color = GameColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    // Tails behind the band.
    final tailPaint = Paint()..color = tone.lip;
    for (final s in [-1.0, 1.0]) {
      final x0 = s < 0 ? 18.0 : w - 18.0;
      final x1 = s < 0 ? -8.0 : w + 8.0;
      final tail = Path()
        ..moveTo(x0, h * 0.25)
        ..lineTo(x1, h * 0.35)
        ..lineTo(x1 + s * -10, h * 0.72)
        ..lineTo(x1, h * 1.1)
        ..lineTo(x0, h * 1.0)
        ..close();
      canvas.drawPath(tail, tailPaint);
      canvas.drawPath(tail, outline);
    }
    final band = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 0, w - 20, h * 0.92),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(tone.face, Colors.white, 0.25)!,
            tone.face,
            tone.lip,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(band.outerRect),
    );
    canvas.drawRRect(band, outline);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.tone != tone;
}

/// Entrance: scales up from [from] with overshoot after [delay].
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.from = 0.4,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double from;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: Curves.easeOut.transform(_c.value),
          child: Transform.scale(
            scale: widget.from + (1 - widget.from) * t,
            child: child,
          ),
        );
      },
    );
  }
}

/// Entrance: slides in from [offset] (in logical pixels) after [delay].
class SlideIn extends StatefulWidget {
  const SlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 40),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<SlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value,
          child: Transform.translate(
            offset: widget.offset * (1 - t),
            child: child,
          ),
        );
      },
    );
  }
}

/// Endless gentle float, e.g. for the next level node.
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child, this.amplitude = 6});

  final Widget child;
  final double amplitude;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, math.sin(_c.value * 2 * math.pi) * widget.amplitude),
        child: child,
      ),
    );
  }
}

/// Number that counts up from 0 to [value].
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    this.format,
    this.size = 22,
    this.delay = Duration.zero,
  });

  final double value;
  final String Function(double v)? format;
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (v) => v.round().toString();
    if (reduceMotion(context)) return GameText(fmt(value), size: size);
    return _Delayed(
      delay: delay,
      builder: (go) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: go ? value : 0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => GameText(fmt(v), size: size),
      ),
    );
  }
}

class _Delayed extends StatefulWidget {
  const _Delayed({required this.delay, required this.builder});

  final Duration delay;
  final Widget Function(bool go) builder;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_go);
}

/// A five-point star path inside [rect].
Path starPath(Rect rect, {double inner = 0.48}) {
  final c = rect.center;
  final r = rect.shortestSide / 2;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// Chunky outlined star filled from the left by [fill] (0–1).
class GameStar extends StatelessWidget {
  const GameStar({super.key, required this.fill, this.size = 64});

  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StarPainter(fill));
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.fill);

  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * 0.06);
    final path = starPath(rect);
    final stroke = size.width * 0.07;
    // Drop shadow.
    canvas.drawPath(
      path.shift(Offset(0, stroke * 0.9)),
      Paint()..color = Colors.black38,
    );
    // Empty socket.
    canvas.drawPath(path, Paint()..color = const Color(0x55000000));
    if (fill > 0) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, 0, size.width * fill.clamp(0.0, 1.0), size.height),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              GameColors.goldLight,
              GameColors.gold,
              GameColors.goldDark,
            ],
            stops: [0, 0.55, 1],
          ).createShader(rect),
      );
      // Shine.
      canvas.drawPath(
        starPath(
          rect.deflate(rect.width * 0.22),
          inner: 0.5,
        ).shift(Offset(-rect.width * 0.04, -rect.height * 0.06)),
        Paint()..color = Colors.white.withValues(alpha: 0.28),
      );
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = GameColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.fill != fill;
}

/// Three stars that pop in one after another, with a sparkle burst on each
/// filled star. The middle star sits higher and bigger.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.stars,
    this.size = 72,
    this.delay = Duration.zero,
  });

  /// Continuous star value 0–3 (e.g. 2.5 = two and a half stars).
  final double stars;
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == 1 ? size * 0.25 : 0),
            child: _StarSlot(
              fill: (stars - i).clamp(0.0, 1.0),
              size: i == 1 ? size * 1.2 : size,
              delay: delay + Duration(milliseconds: 220 * i),
              tilt: (i - 1) * 0.18,
            ),
          ),
      ],
    );
  }
}

class _StarSlot extends StatefulWidget {
  const _StarSlot({
    required this.fill,
    required this.size,
    required this.delay,
    required this.tilt,
  });

  final double fill;
  final double size;
  final Duration delay;
  final double tilt;

  @override
  State<_StarSlot> createState() => _StarSlotState();
}

class _StarSlotState extends State<_StarSlot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.25,
      height: s * 1.25,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pop = Curves.elasticOut.transform(
            (_c.value / 0.7).clamp(0.0, 1.0),
          );
          final burst = ((_c.value - 0.15) / 0.85).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Empty socket always visible.
              Transform.rotate(
                angle: widget.tilt,
                child: GameStar(fill: 0, size: s),
              ),
              if (widget.fill > 0 && burst > 0 && burst < 1)
                CustomPaint(
                  size: Size.square(s * 1.25),
                  painter: _SparklePainter(burst),
                ),
              if (widget.fill > 0)
                Transform.rotate(
                  angle: widget.tilt + (1 - pop) * 0.8,
                  child: Transform.scale(
                    scale: pop,
                    child: GameStar(fill: widget.fill, size: s),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * (0.3 + 0.45 * Curves.easeOut.transform(t));
    final alpha = (1 - t);
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + 0.3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      final dot = size.width * 0.05 * (1 - t * 0.6) * (i.isEven ? 1 : 0.7);
      final paint = Paint()
        ..color = (i.isEven ? GameColors.goldLight : Colors.white).withValues(
          alpha: alpha,
        );
      canvas.drawPath(
        starPath(Rect.fromCircle(center: p, radius: dot * 1.6), inner: 0.4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// Pill showing a counter with a gold star icon (e.g. total stars).
class StarCounter extends StatelessWidget {
  const StarCounter({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        color: const Color(0xAA1E1442),
        border: Border.all(color: GameColors.outline, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(-8, 0),
            child: const GameStar(fill: 1, size: 46),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => GameText('${v.round()}', size: 22),
          ),
        ],
      ),
    );
  }
}

/// Sky with drifting clouds and rolling hills (home background).
class SkyBackground extends StatefulWidget {
  const SkyBackground({super.key, required this.child});

  final Widget child;

  @override
  State<SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<SkyBackground>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _SkyPainter(_c))),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GameColors.skyTop, GameColors.skyBottom],
        ).createShader(rect),
    );
    // Sun glow.
    final sun = Offset(size.width * 0.85, size.height * 0.08);
    canvas.drawCircle(
      sun,
      size.shortestSide * 0.35,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: sun, radius: size.shortestSide * 0.35),
            ),
    );
    // Clouds.
    const clouds = [
      (0.10, 0.12, 1.0, 1.0),
      (0.55, 0.22, 0.7, 1.6),
      (0.30, 0.40, 0.55, 2.2),
      (0.80, 0.50, 0.85, 1.3),
      (0.05, 0.65, 0.6, 1.9),
    ];
    for (final (x, y, scale, speed) in clouds) {
      final w = 180.0 * scale;
      final span = size.width + w * 2;
      final cx = ((x * span + anim.value * span * speed) % span) - w;
      _cloud(canvas, Offset(cx, y * size.height), scale);
    }
    // Hills.
    final h = size.height;
    _hill(canvas, size, h * 0.86, 0.9, GameColors.grassDark);
    _hill(canvas, size, h * 0.91, 1.4, GameColors.grass);
  }

  void _cloud(Canvas canvas, Offset o, double s) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final shade = Paint()..color = const Color(0x33215A8F);
    for (final (dx, dy, r) in const [
      (0.0, 10.0, 28.0),
      (34.0, -6.0, 38.0),
      (76.0, 4.0, 32.0),
      (106.0, 14.0, 22.0),
    ]) {
      canvas.drawCircle(o + Offset(dx, dy + 8) * s, r * s, shade);
    }
    for (final (dx, dy, r) in const [
      (0.0, 10.0, 28.0),
      (34.0, -6.0, 38.0),
      (76.0, 4.0, 32.0),
      (106.0, 14.0, 22.0),
    ]) {
      canvas.drawCircle(o + Offset(dx, dy) * s, r * s, paint);
    }
  }

  void _hill(Canvas canvas, Size size, double y, double freq, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 8) {
      final yy = y + math.sin(x / size.width * math.pi * 2 * freq + freq) * 18;
      path.lineTo(x, yy);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = GameColors.outline.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// Night backdrop with slowly turning light rays (result screen).
class RaysBackground extends StatefulWidget {
  const RaysBackground({super.key, required this.child});

  final Widget child;

  @override
  State<RaysBackground> createState() => _RaysBackgroundState();
}

class _RaysBackgroundState extends State<RaysBackground>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _RaysPainter(_c))),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.1,
          colors: [Color(0xFF6A4FD8), GameColors.night, GameColors.nightDeep],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );
    final c = Offset(size.width / 2, size.height * 0.35);
    final r = size.longestSide;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = anim.value * 2 * math.pi + i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r)
        ..lineTo(c.dx + math.cos(a + 0.18) * r, c.dy + math.sin(a + 0.18) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => false;
}
