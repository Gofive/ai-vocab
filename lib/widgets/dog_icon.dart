import 'package:flutter/material.dart';

class DogIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const DogIcon({super.key, this.size = 24.0, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DogPainter(color: color),
    );
  }
}

class _DogPainter extends CustomPainter {
  final Color? color;

  _DogPainter({this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    // 调色板
    final mainColor = const Color(0xFFE6C49B); // 浅褐色 (Beige)
    final earColor = const Color(0xFF8D6E63); //深褐色
    final darkColor = const Color(0xFF3E2723); // 深黑色

    // 耳朵 (左)
    paint.color = earColor;
    final leftEarPath = Path();
    leftEarPath.moveTo(w * 0.2, h * 0.25);
    leftEarPath.quadraticBezierTo(w * 0.05, h * 0.45, w * 0.15, h * 0.6);
    leftEarPath.quadraticBezierTo(w * 0.3, h * 0.65, w * 0.35, h * 0.35);
    canvas.drawPath(leftEarPath, paint);

    // 耳朵 (右)
    final rightEarPath = Path();
    rightEarPath.moveTo(w * 0.8, h * 0.25);
    rightEarPath.quadraticBezierTo(w * 0.95, h * 0.45, w * 0.85, h * 0.6);
    rightEarPath.quadraticBezierTo(w * 0.7, h * 0.65, w * 0.65, h * 0.35);
    canvas.drawPath(rightEarPath, paint);

    // 脸部
    paint.color = mainColor;
    final faceRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.55),
      width: w * 0.7,
      height: h * 0.65,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(w * 0.35)),
      paint,
    );

    // 眼睛
    paint.color = darkColor;
    canvas.drawCircle(Offset(w * 0.38, h * 0.5), w * 0.06, paint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.5), w * 0.06, paint);

    // 鼻子
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.65),
        width: w * 0.2,
        height: h * 0.12,
      ),
      paint,
    );

    // 嘴巴 (简单的线条)
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = w * 0.03;
    final mouthPath = Path();
    mouthPath.moveTo(w * 0.5, h * 0.71);
    mouthPath.lineTo(w * 0.5, h * 0.75);
    mouthPath.quadraticBezierTo(w * 0.4, h * 0.8, w * 0.35, h * 0.75);
    mouthPath.moveTo(w * 0.5, h * 0.75);
    mouthPath.quadraticBezierTo(w * 0.6, h * 0.8, w * 0.65, h * 0.75);
    canvas.drawPath(mouthPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
