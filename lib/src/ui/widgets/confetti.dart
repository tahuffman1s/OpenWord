import 'dart:math';

import 'package:flutter/material.dart';

/// A short shower of coloured pieces over whatever it wraps: the moment
/// a goal is met or a badge won. Plays once when built and gets out of
/// the way; it never takes a tap.
class Confetti extends StatefulWidget {
  const Confetti({
    super.key,
    required this.child,
    this.play = true,
    this.duration = const Duration(milliseconds: 2400),
    this.pieces = 48,
  });

  final Widget child;

  /// Whether to shower at all: false leaves the child alone.
  final bool play;
  final Duration duration;
  final int pieces;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = Random(7);
    _pieces = [
      for (var i = 0; i < widget.pieces; i++) _Piece.random(random, i),
    ];
    if (widget.play) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colours = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
    ];
    return Stack(
      children: [
        widget.child,
        if (widget.play)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _controller.isCompleted
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _ConfettiPainter(
                          pieces: _pieces,
                          t: _controller.value,
                          colours: colours,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.drift,
    required this.delay,
    required this.spin,
    required this.size,
    required this.colour,
  });

  /// Where it starts across the width, 0 to 1.
  final double x;

  /// How far it drifts sideways on the way down, as a share of the width.
  final double drift;

  /// How far into the shower it sets off, 0 to 0.4.
  final double delay;
  final double spin;
  final double size;
  final int colour;

  factory _Piece.random(Random random, int index) => _Piece(
    x: random.nextDouble(),
    drift: (random.nextDouble() - 0.5) * 0.3,
    delay: random.nextDouble() * 0.4,
    spin: (random.nextDouble() - 0.5) * 12,
    size: 6 + random.nextDouble() * 6,
    colour: index,
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.pieces,
    required this.t,
    required this.colours,
  });

  final List<_Piece> pieces;
  final double t;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final piece in pieces) {
      final local = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      // Falls faster as it goes, the way a thing does, and fades at the end.
      final y = local * local * (size.height + piece.size * 2) - piece.size;
      final x = size.width * (piece.x + piece.drift * local);
      final fade = local > 0.75 ? (1 - local) / 0.25 : 1.0;
      paint.color = colours[piece.colour % colours.length].withValues(
        alpha: fade,
      );
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(piece.spin * local)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: piece.size,
              height: piece.size * 0.6,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
