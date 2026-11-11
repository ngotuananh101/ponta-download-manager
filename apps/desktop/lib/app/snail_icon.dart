import 'package:flutter/material.dart';

/// A small snail icon, drawn with a [CustomPainter].
///
/// Flutter's Material Icons has no snail, and snail mode needs one for
/// its status-bar toggle. The snail is a solid silhouette (shell +
/// body + head + two antennae) drawn in a 24x24 box and scaled to
/// [size], so it stays crisp at any size and needs no asset or font.
class SnailIcon extends StatelessWidget {
  const SnailIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SnailIconPainter(color),
    );
  }
}

class _SnailIconPainter extends CustomPainter {
  _SnailIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Draw in a 24x24 box, scaled to the requested size.
    canvas.scale(size.width / 24);
    // Shell: the big round shell on the left.
    canvas.drawCircle(const Offset(9.5, 12), 6.5, fill);
    // Body: a thick rounded line under the shell, extending right.
    final body = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(4, 18.5), const Offset(19.5, 18.5), body);
    // Head: a small bump at the right end of the body.
    canvas.drawCircle(const Offset(19.5, 16), 2.5, fill);
    // Antennae: two short lines from the head, with dots at the tips.
    final antenna = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(18.5, 14), const Offset(17, 10.5), antenna);
    canvas.drawLine(const Offset(20.5, 14), const Offset(22, 10.5), antenna);
    canvas.drawCircle(const Offset(17, 10.5), 0.9, fill);
    canvas.drawCircle(const Offset(22, 10.5), 0.9, fill);
  }

  @override
  bool shouldRepaint(covariant _SnailIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
