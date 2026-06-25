import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original cartoon avatars inspired by classic literary archetypes
/// (wizard student, ring-bearer, detective, etc.) — not licensed characters.
class LiteraryAvatarInfo {
  const LiteraryAvatarInfo(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

const List<LiteraryAvatarInfo> kLiteraryAvatars = [
  LiteraryAvatarInfo('Wizard Student', 'Round glasses & spellbook'),
  LiteraryAvatarInfo('Ring-Bearer', 'Cloak & curly hair'),
  LiteraryAvatarInfo('Detective', 'Deerstalker & magnifier'),
  LiteraryAvatarInfo('Princess', 'Crown & royal braid'),
  LiteraryAvatarInfo('Pirate Captain', 'Tricorn & eyepatch'),
  LiteraryAvatarInfo('Mad Hatter', 'Tall hat & tea cup'),
  LiteraryAvatarInfo('Brave Knight', 'Helm & shield'),
  LiteraryAvatarInfo('Story Dragon', 'Friendly book dragon'),
];

int clampLiteraryAvatarIndex(int index) =>
    index % kLiteraryAvatars.length;

/// Cartoon literary character avatar drawn with [CustomPainter].
class LiteraryCharacterAvatar extends StatelessWidget {
  const LiteraryCharacterAvatar({
    super.key,
    required this.index,
    this.size = 56,
    this.selected = false,
  });

  final int index;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final i = clampLiteraryAvatarIndex(index);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: const Color(0xFFE8B86D), width: 3)
            : Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFFE8B86D).withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _LiteraryCharacterPainter(i),
          size: Size.square(size),
        ),
      ),
    );
  }
}

class _LiteraryCharacterPainter extends CustomPainter {
  _LiteraryCharacterPainter(this.index);

  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2;

    _fillCircle(canvas, Offset(cx, cy), r, const Color(0xFF1A1A22));

    switch (index) {
      case 0:
        _paintWizardStudent(canvas, size);
      case 1:
        _paintRingBearer(canvas, size);
      case 2:
        _paintDetective(canvas, size);
      case 3:
        _paintPrincess(canvas, size);
      case 4:
        _paintPirate(canvas, size);
      case 5:
        _paintMadHatter(canvas, size);
      case 6:
        _paintKnight(canvas, size);
      default:
        _paintStoryDragon(canvas, size);
    }
  }

  void _paintWizardStudent(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.08), s * 0.28, const Color(0xFFFFD7B0));
    _fillArc(
      canvas,
      Offset(cx, cy - s * 0.02),
      s * 0.30,
      math.pi,
      math.pi,
      const Color(0xFF2B2118),
    );
    _strokeRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.02), width: s * 0.34, height: s * 0.14),
      const Color(0xFF8B8B8B),
      2.5,
    );
    _fillCircle(canvas, Offset(cx - s * 0.09, cy + s * 0.02), s * 0.055, Colors.white);
    _fillCircle(canvas, Offset(cx + s * 0.09, cy + s * 0.02), s * 0.055, Colors.white);
    _fillCircle(canvas, Offset(cx - s * 0.09, cy + s * 0.02), s * 0.028, const Color(0xFF3D2914));
    _fillCircle(canvas, Offset(cx + s * 0.09, cy + s * 0.02), s * 0.028, const Color(0xFF3D2914));

  // Striped scarf
    final scarf = Paint()..color = const Color(0xFF7A1F3D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.18, cy + s * 0.22, s * 0.36, s * 0.08),
        Radius.circular(s * 0.04),
      ),
      scarf,
    );
    final gold = Paint()..color = const Color(0xFFD4AF37);
    canvas.drawRect(
      Rect.fromLTWH(cx - s * 0.18, cy + s * 0.24, s * 0.12, s * 0.04),
      gold,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + s * 0.02, cy + s * 0.24, s * 0.12, s * 0.04),
      gold,
    );

    _fillPath(canvas, _triangle(Offset(cx, cy - s * 0.28), s * 0.16, s * 0.20), const Color(0xFF4A2F7A));
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.34), width: s * 0.42, height: s * 0.22),
      s * 0.06,
      const Color(0xFF3D2563),
    );

  // Wand + book
    _strokeLine(canvas, Offset(cx + s * 0.24, cy + s * 0.10), Offset(cx + s * 0.34, cy - s * 0.08), const Color(0xFF8B5A2B), 2.5);
    _fillCircle(canvas, Offset(cx + s * 0.35, cy - s * 0.09), s * 0.03, const Color(0xFFFFE566));
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx - s * 0.28, cy + s * 0.30), width: s * 0.12, height: s * 0.16),
      2,
      const Color(0xFF8B4513),
    );
  }

  void _paintRingBearer(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.10), s * 0.27, const Color(0xFFFFDAB5));
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * 0.55;
      _fillCircle(
        canvas,
        Offset(cx + math.cos(a) * s * 0.18, cy - s * 0.02 + math.sin(a) * s * 0.14),
        s * 0.05,
        const Color(0xFF6B3E1E),
      );
    }
    _fillCircle(canvas, Offset(cx - s * 0.08, cy + s * 0.08), s * 0.025, const Color(0xFF3D2914));
    _fillCircle(canvas, Offset(cx + s * 0.08, cy + s * 0.08), s * 0.025, const Color(0xFF3D2914));
    _strokeArc(canvas, Offset(cx, cy + s * 0.14), s * 0.08, 0.2, math.pi - 0.2, const Color(0xFF8B4513), 2);

    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.34), width: s * 0.46, height: s * 0.24),
      s * 0.08,
      const Color(0xFF2F5D3A),
    );
    _fillCircle(canvas, Offset(cx + s * 0.18, cy + s * 0.28), s * 0.05, const Color(0xFFFFD700));
  }

  void _paintDetective(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.12), s * 0.24, const Color(0xFFFFE0C2));
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx - s * 0.28, cy - s * 0.02)
        ..lineTo(cx, cy - s * 0.22)
        ..lineTo(cx + s * 0.28, cy - s * 0.02)
        ..lineTo(cx + s * 0.22, cy + s * 0.04)
        ..lineTo(cx - s * 0.22, cy + s * 0.04)
        ..close(),
      const Color(0xFF6D4C2C),
    );
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx - s * 0.12, cy - s * 0.20)
        ..lineTo(cx, cy - s * 0.30)
        ..lineTo(cx + s * 0.12, cy - s * 0.20)
        ..close(),
      const Color(0xFF4E342E),
    );
    _fillCircle(canvas, Offset(cx - s * 0.07, cy + s * 0.10), s * 0.022, const Color(0xFF2D1A0E));
    _fillCircle(canvas, Offset(cx + s * 0.07, cy + s * 0.10), s * 0.022, const Color(0xFF2D1A0E));

    _strokeCircle(canvas, Offset(cx + s * 0.24, cy + s * 0.18), s * 0.10, const Color(0xFF90A4AE), 2.5);
    _strokeLine(canvas, Offset(cx + s * 0.24, cy + s * 0.28), Offset(cx + s * 0.24, cy + s * 0.38), const Color(0xFF8B5A2B), 2.5);
  }

  void _paintPrincess(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.10), s * 0.26, const Color(0xFFFFE4EC));
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx, cy - s * 0.18)
        ..quadraticBezierTo(cx - s * 0.22, cy + s * 0.02, cx - s * 0.18, cy + s * 0.22)
        ..quadraticBezierTo(cx, cy + s * 0.10, cx + s * 0.18, cy + s * 0.22)
        ..quadraticBezierTo(cx + s * 0.22, cy + s * 0.02, cx, cy - s * 0.18)
        ..close(),
      const Color(0xFFFFB7C5),
    );
    _fillPath(
      canvas,
      _crownPath(Offset(cx, cy - s * 0.20), s * 0.22),
      const Color(0xFFFFD54F),
    );
    _fillCircle(canvas, Offset(cx - s * 0.08, cy + s * 0.08), s * 0.028, const Color(0xFF5D3A4A));
    _fillCircle(canvas, Offset(cx + s * 0.08, cy + s * 0.08), s * 0.028, const Color(0xFF5D3A4A));
    _strokeArc(canvas, Offset(cx, cy + s * 0.14), s * 0.06, 0.3, math.pi - 0.3, const Color(0xFFE57399), 2);

    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.36), width: s * 0.40, height: s * 0.20),
      s * 0.06,
      const Color(0xFF9C27B0),
    );
  }

  void _paintPirate(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.10), s * 0.26, const Color(0xFFFFD7B0));
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx - s * 0.30, cy - s * 0.04)
        ..lineTo(cx, cy - s * 0.24)
        ..lineTo(cx + s * 0.30, cy - s * 0.04)
        ..lineTo(cx + s * 0.26, cy + s * 0.06)
        ..lineTo(cx - s * 0.26, cy + s * 0.06)
        ..close(),
      const Color(0xFF1F1F1F),
    );
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.02), width: s * 0.34, height: s * 0.10),
      s * 0.05,
      const Color(0xFF8B1E1E),
    );
    _fillCircle(canvas, Offset(cx - s * 0.10, cy + s * 0.08), s * 0.028, const Color(0xFF2D1A0E));
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx + s * 0.10, cy + s * 0.08), width: s * 0.12, height: s * 0.08),
      s * 0.04,
      const Color(0xFF111111),
    );
    _strokeArc(canvas, Offset(cx, cy + s * 0.16), s * 0.07, 0.2, math.pi - 0.2, const Color(0xFF5D3A1A), 2.5);
  }

  void _paintMadHatter(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy - s * 0.14), width: s * 0.34, height: s * 0.28),
      s * 0.04,
      const Color(0xFF5D4037),
    );
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy - s * 0.28), width: s * 0.30, height: s * 0.18),
      s * 0.05,
      const Color(0xFF7B1FA2),
    );
    _fillRoundRect(
      canvas,
      Rect.fromLTWH(cx - s * 0.18, cy - s * 0.36, s * 0.36, s * 0.05),
      s * 0.02,
      const Color(0xFFFFD54F),
    );

    _fillCircle(canvas, Offset(cx, cy + s * 0.12), s * 0.24, const Color(0xFFFFE0C2));
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx - s * 0.20, cy + s * 0.02)
        ..quadraticBezierTo(cx, cy - s * 0.08, cx + s * 0.20, cy + s * 0.02)
        ..lineTo(cx + s * 0.18, cy + s * 0.10)
        ..quadraticBezierTo(cx, cy + s * 0.04, cx - s * 0.18, cy + s * 0.10)
        ..close(),
      const Color(0xFFB5651D),
    );
    _fillCircle(canvas, Offset(cx - s * 0.07, cy + s * 0.10), s * 0.022, const Color(0xFF2D1A0E));
    _fillCircle(canvas, Offset(cx + s * 0.07, cy + s * 0.10), s * 0.022, const Color(0xFF2D1A0E));

    _fillCircle(canvas, Offset(cx - s * 0.24, cy + s * 0.28), s * 0.07, const Color(0xFFECEFF1));
    _strokeCircle(canvas, Offset(cx - s * 0.24, cy + s * 0.28), s * 0.07, const Color(0xFF90A4AE), 1.5);
  }

  void _paintKnight(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.02), width: s * 0.38, height: s * 0.34),
      s * 0.10,
      const Color(0xFFB0BEC5),
    );
    _fillRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.04), width: s * 0.10, height: s * 0.14),
      const Color(0xFF263238),
    );
    _fillCircle(canvas, Offset(cx - s * 0.10, cy + s * 0.02), s * 0.04, const Color(0xFF90A4AE));
    _fillCircle(canvas, Offset(cx + s * 0.10, cy + s * 0.02), s * 0.04, const Color(0xFF90A4AE));
    _fillPath(
      canvas,
      Path()
        ..moveTo(cx - s * 0.14, cy - s * 0.10)
        ..lineTo(cx, cy - s * 0.24)
        ..lineTo(cx + s * 0.14, cy - s * 0.10)
        ..close(),
      const Color(0xFFCFD8DC),
    );
    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx + s * 0.26, cy + s * 0.22), width: s * 0.14, height: s * 0.18),
      3,
      const Color(0xFF546E7A),
    );
    _fillCircle(canvas, Offset(cx + s * 0.26, cy + s * 0.22), s * 0.04, const Color(0xFFE8B86D));
  }

  void _paintStoryDragon(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.shortestSide;

    _fillCircle(canvas, Offset(cx, cy + s * 0.06), s * 0.30, const Color(0xFF66BB6A));
    _fillCircle(canvas, Offset(cx - s * 0.14, cy - s * 0.02), s * 0.09, const Color(0xFF43A047));
    _fillCircle(canvas, Offset(cx + s * 0.14, cy - s * 0.02), s * 0.09, const Color(0xFF43A047));
    _fillCircle(canvas, Offset(cx - s * 0.10, cy + s * 0.04), s * 0.05, Colors.white);
    _fillCircle(canvas, Offset(cx + s * 0.10, cy + s * 0.04), s * 0.05, Colors.white);
    _fillCircle(canvas, Offset(cx - s * 0.10, cy + s * 0.04), s * 0.025, const Color(0xFF1B5E20));
    _fillCircle(canvas, Offset(cx + s * 0.10, cy + s * 0.04), s * 0.025, const Color(0xFF1B5E20));
    _strokeArc(canvas, Offset(cx, cy + s * 0.14), s * 0.08, 0.3, math.pi - 0.3, const Color(0xFF2E7D32), 2.5);

    _fillRoundRect(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy + s * 0.30), width: s * 0.18, height: s * 0.12),
      2,
      const Color(0xFF8D6E63),
    );
    for (var i = 0; i < 3; i++) {
      _fillRect(
        canvas,
        Rect.fromLTWH(cx - s * 0.06 + i * s * 0.05, cy + s * 0.27, s * 0.03, s * 0.06),
        Colors.white,
      );
    }
  }

  Path _crownPath(Offset c, double w) {
    return Path()
      ..moveTo(c.dx - w, c.dy + w * 0.3)
      ..lineTo(c.dx - w * 0.6, c.dy - w * 0.2)
      ..lineTo(c.dx - w * 0.3, c.dy + w * 0.05)
      ..lineTo(c.dx, c.dy - w * 0.45)
      ..lineTo(c.dx + w * 0.3, c.dy + w * 0.05)
      ..lineTo(c.dx + w * 0.6, c.dy - w * 0.2)
      ..lineTo(c.dx + w, c.dy + w * 0.3)
      ..close();
  }

  Path _triangle(Offset apex, double halfW, double h) {
    return Path()
      ..moveTo(apex.dx, apex.dy - h)
      ..lineTo(apex.dx - halfW, apex.dy)
      ..lineTo(apex.dx + halfW, apex.dy)
      ..close();
  }

  void _fillCircle(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  void _strokeCircle(Canvas canvas, Offset c, double r, Color color, double w) {
    canvas.drawCircle(c, r, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w);
  }

  void _fillRect(Canvas canvas, Rect r, Color color) {
    canvas.drawRect(r, Paint()..color = color);
  }

  void _fillRoundRect(Canvas canvas, Rect r, double radius, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void _strokeRoundRect(Canvas canvas, Rect r, Color color, double w) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(8)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  void _fillPath(Canvas canvas, Path path, Color color) {
    canvas.drawPath(path, Paint()..color = color);
  }

  void _fillArc(
    Canvas canvas,
    Offset c,
    double r,
    double start,
    double sweep,
    Color color,
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      true,
      Paint()..color = color,
    );
  }

  void _strokeArc(
    Canvas canvas,
    Offset c,
    double r,
    double start,
    double sweep,
    Color color,
    double w,
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  void _strokeLine(Canvas canvas, Offset a, Offset b, Color color, double w) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LiteraryCharacterPainter oldDelegate) =>
      oldDelegate.index != index;
}
