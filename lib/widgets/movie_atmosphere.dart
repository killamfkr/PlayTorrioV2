import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MOVIE ATMOSPHERE SYSTEM
//  Extracts palette → animates backdrop → spawns genre particles → glows poster
// ═══════════════════════════════════════════════════════════════════════════════

/// Extracted palette colors for a movie, used across the atmosphere system.
class AtmosphereColors {
  final Color dominant;
  final Color vibrant;
  final Color muted;
  final Color accent;

  const AtmosphereColors({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.accent,
  });

  static const fallback = AtmosphereColors(
    dominant: Color(0xFF7C4DFF),
    vibrant: Color(0xFF00E5FF),
    muted: Color(0xFF2A2A3E),
    accent: Color(0xFF7C4DFF),
  );
}

/// Extracts the dominant palette from a movie poster/backdrop URL.
Future<AtmosphereColors> extractAtmosphereColors(String imageUrl) async {
  try {
    final generator = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl),
      size: const Size(100, 150), // small for speed
      maximumColorCount: 8,
    );

    final dominant = generator.dominantColor?.color ?? const Color(0xFF7C4DFF);
    final vibrant = generator.vibrantColor?.color ?? generator.lightVibrantColor?.color ?? dominant;
    final muted = generator.mutedColor?.color ?? generator.darkMutedColor?.color ?? const Color(0xFF2A2A3E);
    final accent = generator.lightVibrantColor?.color ?? generator.vibrantColor?.color ?? vibrant;

    return AtmosphereColors(
      dominant: dominant,
      vibrant: vibrant,
      muted: muted,
      accent: accent,
    );
  } catch (_) {
    return AtmosphereColors.fallback;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  KEN BURNS BACKDROP — slow cinematic pan & zoom
// ═══════════════════════════════════════════════════════════════════════════════

class KenBurnsBackdrop extends StatefulWidget {
  final String imageUrl;
  final AtmosphereColors? colors;
  final double blurSigma;

  const KenBurnsBackdrop({
    super.key,
    required this.imageUrl,
    this.colors,
    this.blurSigma = 28,
  });

  @override
  State<KenBurnsBackdrop> createState() => _KenBurnsBackdropState();
}

class _KenBurnsBackdropState extends State<KenBurnsBackdrop> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Alignment> _alignAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 25),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _alignAnimation = AlignmentTween(
      begin: const Alignment(-0.5, -0.3),
      end: const Alignment(0.5, 0.2),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Animated backdrop
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              alignment: _alignAnimation.value,
              child: child,
            );
          },
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget: (c, u, e) => Container(color: const Color(0xFF0A0A1A)),
          ),
        ),

        // Blur layer
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
          child: Container(color: Colors.transparent),
        ),

        // Gradient overlay — strongly tinted with movie's dominant color
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(const Color(0xFF050510), colors?.dominant ?? const Color(0xFF050510), 0.35)!.withValues(alpha: 0.75),
                Color.lerp(const Color(0xFF000000), colors?.muted ?? const Color(0xFF000000), 0.15)!.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),

        // Strong radial glow from top using vibrant color
        if (colors != null) ...[
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.7),
                radius: 1.4,
                colors: [
                  colors.vibrant.withValues(alpha: 0.18),
                  colors.vibrant.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
          // Secondary accent glow from bottom-right
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.9),
                radius: 1.0,
                colors: [
                  colors.dominant.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GENRE PARTICLES — ambient floating elements based on movie genre
// ═══════════════════════════════════════════════════════════════════════════════

enum _ParticleType { ember, snow, dataStream, orb, bokeh, dust }

_ParticleType _typeForGenres(List<String> genres) {
  final g = genres.map((e) => e.toLowerCase()).toSet();
  if (g.any((e) => ['science fiction', 'sci-fi'].contains(e))) return _ParticleType.dataStream;
  if (g.any((e) => ['action', 'war', 'western'].contains(e))) return _ParticleType.ember;
  if (g.any((e) => ['drama', 'thriller', 'crime', 'mystery', 'horror'].contains(e))) return _ParticleType.snow;
  if (g.any((e) => ['fantasy', 'animation'].contains(e))) return _ParticleType.orb;
  if (g.any((e) => ['romance', 'music'].contains(e))) return _ParticleType.bokeh;
  return _ParticleType.dust;
}

class _Particle {
  double x, y, size, speed, opacity, phase;
  double dx; // horizontal drift
  _Particle({
    required this.x, required this.y, required this.size,
    required this.speed, required this.opacity, required this.phase,
    this.dx = 0,
  });
}

class GenreParticles extends StatefulWidget {
  final List<String> genres;
  final AtmosphereColors? colors;

  const GenreParticles({super.key, required this.genres, this.colors});

  @override
  State<GenreParticles> createState() => _GenreParticlesState();
}

class _GenreParticlesState extends State<GenreParticles> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  late _ParticleType _type;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _type = _typeForGenres(widget.genres);
    _particles = List.generate(_particleCount, (_) => _spawnParticle(randomY: true));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  int get _particleCount {
    switch (_type) {
      case _ParticleType.ember: return 35;
      case _ParticleType.snow: return 40;
      case _ParticleType.dataStream: return 20;
      case _ParticleType.orb: return 18;
      case _ParticleType.bokeh: return 22;
      case _ParticleType.dust: return 28;
    }
  }

  _Particle _spawnParticle({bool randomY = false}) {
    switch (_type) {
      case _ParticleType.ember:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : 1.0 + _rand.nextDouble() * 0.1,
          size: 2.5 + _rand.nextDouble() * 4.0,
          speed: 0.25 + _rand.nextDouble() * 0.35,
          opacity: 0.5 + _rand.nextDouble() * 0.5,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.12,
        );
      case _ParticleType.snow:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : -_rand.nextDouble() * 0.1,
          size: 1.5 + _rand.nextDouble() * 3.0,
          speed: 0.08 + _rand.nextDouble() * 0.15,
          opacity: 0.25 + _rand.nextDouble() * 0.4,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.05,
        );
      case _ParticleType.dataStream:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : 1.0 + _rand.nextDouble() * 0.1,
          size: 1.5 + _rand.nextDouble() * 2.0,
          speed: 0.4 + _rand.nextDouble() * 0.6,
          opacity: 0.3 + _rand.nextDouble() * 0.5,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.01,
        );
      case _ParticleType.orb:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : 0.2 + _rand.nextDouble() * 0.6,
          size: 6.0 + _rand.nextDouble() * 10.0,
          speed: 0.03 + _rand.nextDouble() * 0.06,
          opacity: 0.15 + _rand.nextDouble() * 0.3,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.03,
        );
      case _ParticleType.bokeh:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : 0.1 + _rand.nextDouble() * 0.8,
          size: 8.0 + _rand.nextDouble() * 16.0,
          speed: 0.015 + _rand.nextDouble() * 0.04,
          opacity: 0.1 + _rand.nextDouble() * 0.2,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.02,
        );
      case _ParticleType.dust:
        return _Particle(
          x: _rand.nextDouble(),
          y: randomY ? _rand.nextDouble() : _rand.nextDouble(),
          size: 1.5 + _rand.nextDouble() * 2.5,
          speed: 0.05 + _rand.nextDouble() * 0.1,
          opacity: 0.2 + _rand.nextDouble() * 0.3,
          phase: _rand.nextDouble() * pi * 2,
          dx: (_rand.nextDouble() - 0.5) * 0.03,
        );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            type: _type,
            colors: widget.colors ?? AtmosphereColors.fallback,
            tick: _controller.value,
            onUpdate: _updateParticles,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  void _updateParticles(Size size) {
    final dt = 1.0 / 60.0; // ~60fps tick
    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.phase += dt * 1.5;

      // Movement per type
      if (_type == _ParticleType.dataStream) {
        // Rising data streams — fast upward lines
        p.y -= p.speed * dt;
        p.x += sin(p.phase * 3) * 0.0003 + p.dx * dt;
        // Flicker
        p.opacity = (0.3 + sin(p.phase * 4) * 0.3).clamp(0.1, 0.8);
      } else if (_type == _ParticleType.ember) {
        p.y -= p.speed * dt;
        p.x += sin(p.phase * 2) * 0.002 + p.dx * dt;
      } else if (_type == _ParticleType.snow) {
        p.y += p.speed * dt;
        p.x += sin(p.phase * 1.5) * 0.0015 + p.dx * dt;
      } else {
        p.y -= p.speed * dt * 0.5;
        p.x += sin(p.phase) * 0.001 + p.dx * dt;
      }

      // Pulsing opacity for orbs/bokeh
      if (_type == _ParticleType.orb || _type == _ParticleType.bokeh) {
        p.opacity = (0.15 + sin(p.phase) * 0.15).clamp(0.05, 0.4);
      }

      // Recycle
      if (p.y < -0.05 || p.y > 1.05 || p.x < -0.05 || p.x > 1.05) {
        _particles[i] = _spawnParticle();
      }
    }
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final _ParticleType type;
  final AtmosphereColors colors;
  final double tick;
  final void Function(Size) onUpdate;

  _ParticlePainter({
    required this.particles,
    required this.type,
    required this.colors,
    required this.tick,
    required this.onUpdate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    onUpdate(size);

    final paint = Paint();
    for (final p in particles) {
      if (p.opacity < 0.01) continue;

      final px = p.x * size.width;
      final py = p.y * size.height;
      final Color color;

      switch (type) {
        case _ParticleType.ember:
          color = Color.lerp(colors.vibrant, const Color(0xFFFF6D00), 0.5)!;
          // Outer glow
          paint
            ..color = color.withValues(alpha: p.opacity * 0.6)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 1.5);
          canvas.drawCircle(Offset(px, py), p.size * 1.8, paint);
          // Core
          paint
            ..color = color.withValues(alpha: p.opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.5);
          canvas.drawCircle(Offset(px, py), p.size, paint);
          // Hot white center
          paint
            ..color = Colors.white.withValues(alpha: p.opacity * 0.8)
            ..maskFilter = null;
          canvas.drawCircle(Offset(px, py), p.size * 0.35, paint);
          break;

        case _ParticleType.snow:
          color = Colors.white;
          // Soft outer glow
          paint
            ..color = color.withValues(alpha: p.opacity * 0.3)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 1.2);
          canvas.drawCircle(Offset(px, py), p.size * 1.5, paint);
          // Solid core
          paint
            ..color = color.withValues(alpha: p.opacity)
            ..maskFilter = null;
          canvas.drawCircle(Offset(px, py), p.size, paint);
          break;

        case _ParticleType.dataStream:
          // Rising vertical lines like digital rain
          color = colors.accent;
          final trailLen = 12.0 + p.size * 6;
          // Trail (fading upward)
          paint
            ..shader = ui.Gradient.linear(
              Offset(px, py - trailLen),
              Offset(px, py),
              [color.withValues(alpha: 0), color.withValues(alpha: p.opacity)],
            )
            ..strokeWidth = p.size * 0.6
            ..style = PaintingStyle.stroke
            ..maskFilter = null;
          canvas.drawLine(Offset(px, py - trailLen), Offset(px, py), paint);
          paint.shader = null;
          // Bright head
          paint
            ..color = Colors.white.withValues(alpha: p.opacity * 0.9)
            ..style = PaintingStyle.fill
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2);
          canvas.drawCircle(Offset(px, py), p.size * 0.5, paint);
          break;

        case _ParticleType.orb:
          color = colors.vibrant;
          // Big soft glow
          paint
            ..color = color.withValues(alpha: p.opacity * 0.4)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 2.5);
          canvas.drawCircle(Offset(px, py), p.size * 2, paint);
          // Inner bright
          paint
            ..color = color.withValues(alpha: p.opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 1.0);
          canvas.drawCircle(Offset(px, py), p.size, paint);
          break;

        case _ParticleType.bokeh:
          color = Color.lerp(colors.vibrant, colors.accent, 0.3)!;
          // Outer glow ring
          paint
            ..color = color.withValues(alpha: p.opacity * 0.5)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawCircle(Offset(px, py), p.size, paint);
          // Filled center
          paint
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: p.opacity * 0.2)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.4);
          canvas.drawCircle(Offset(px, py), p.size * 0.7, paint);
          break;

        case _ParticleType.dust:
          color = Color.lerp(colors.muted, colors.vibrant, 0.3)!;
          paint
            ..color = color.withValues(alpha: p.opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.8);
          canvas.drawCircle(Offset(px, py), p.size, paint);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  POSTER FRAME — breathing glow + genre-animated border
// ═══════════════════════════════════════════════════════════════════════════════

class PosterGlow extends StatefulWidget {
  final Widget child;
  final AtmosphereColors? colors;
  final List<String> genres;
  final double width;
  final double height;
  final double borderRadius;

  const PosterGlow({
    super.key,
    required this.child,
    this.colors,
    this.genres = const [],
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<PosterGlow> createState() => _PosterGlowState();
}

class _PosterGlowState extends State<PosterGlow> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final dominant = colors?.dominant ?? const Color(0xFF7C4DFF);
    final vibrant = colors?.vibrant ?? const Color(0xFF00E5FF);
    final accent = colors?.accent ?? vibrant;
    final type = _typeForGenres(widget.genres);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final breathe = 0.4 + sin(t * pi * 2) * 0.4; // 0.0 → 0.8

        return CustomPaint(
          painter: _PosterBorderPainter(
            type: type,
            dominant: dominant,
            vibrant: vibrant,
            accent: accent,
            progress: t,
            breathe: breathe,
            borderRadius: widget.borderRadius,
            width: widget.width,
            height: widget.height,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.5), // border inset
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _PosterBorderPainter extends CustomPainter {
  final _ParticleType type;
  final Color dominant, vibrant, accent;
  final double progress, breathe, borderRadius, width, height;

  _PosterBorderPainter({
    required this.type,
    required this.dominant,
    required this.vibrant,
    required this.accent,
    required this.progress,
    required this.breathe,
    required this.borderRadius,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Outer glow (all types)
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + breathe * 8)
      ..color = dominant.withValues(alpha: 0.3 + breathe * 0.25);
    canvas.drawRRect(rrect, glowPaint);

    switch (type) {
      case _ParticleType.ember:
        // Flickering fire border — gradient rotates, orange->red->yellow
        final sweep = ui.Gradient.sweep(
          rect.center,
          [
            const Color(0xFFFF6D00).withValues(alpha: 0.7 + breathe * 0.3),
            const Color(0xFFFF1744).withValues(alpha: 0.5 + breathe * 0.3),
            vibrant.withValues(alpha: 0.6),
            const Color(0xFFFFAB00).withValues(alpha: 0.7 + breathe * 0.3),
            const Color(0xFFFF6D00).withValues(alpha: 0.7 + breathe * 0.3),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
          TileMode.clamp,
          0.0, pi * 2,
          _rotationMatrix(progress * pi * 2, rect.center),
        );
        paint.shader = sweep;
        paint.strokeWidth = 2.0 + breathe * 1.5;
        canvas.drawRRect(rrect, paint);
        break;

      case _ParticleType.snow:
        // Cold misty border — fading white/blue with crawling highlights
        final sweep = ui.Gradient.sweep(
          rect.center,
          [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.5 + breathe * 0.3),
            const Color(0xFF90CAF9).withValues(alpha: 0.3),
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.5 + breathe * 0.3),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
          TileMode.clamp,
          0.0, pi * 2,
          _rotationMatrix(progress * pi * 2 * 0.5, rect.center), // slower
        );
        paint.shader = sweep;
        paint.strokeWidth = 1.5 + breathe * 0.8;
        canvas.drawRRect(rrect, paint);
        break;

      case _ParticleType.dataStream:
        // Scanning beam border — a bright accent segment sweeps around
        final sweepAngle = progress * pi * 2;
        final sweep = ui.Gradient.sweep(
          rect.center,
          [
            Colors.transparent,
            accent.withValues(alpha: 0.0),
            accent.withValues(alpha: 0.9),
            Colors.white.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.9),
            accent.withValues(alpha: 0.0),
            Colors.transparent,
          ],
          [0.0, 0.30, 0.42, 0.5, 0.58, 0.70, 1.0],
          TileMode.clamp,
          0.0, pi * 2,
          _rotationMatrix(sweepAngle, rect.center),
        );
        paint.shader = sweep;
        paint.strokeWidth = 2.0;
        canvas.drawRRect(rrect, paint);
        // Faint base border
        paint
          ..shader = null
          ..color = accent.withValues(alpha: 0.12)
          ..strokeWidth = 1.0;
        canvas.drawRRect(rrect, paint);
        break;

      case _ParticleType.orb:
        // Shimmering prismatic border — rotating rainbow-ish from the palette
        final sweep = ui.Gradient.sweep(
          rect.center,
          [
            vibrant.withValues(alpha: 0.6 + breathe * 0.3),
            accent.withValues(alpha: 0.5),
            dominant.withValues(alpha: 0.7 + breathe * 0.2),
            Color.lerp(vibrant, Colors.white, 0.3)!.withValues(alpha: 0.6),
            vibrant.withValues(alpha: 0.6 + breathe * 0.3),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
          TileMode.clamp,
          0.0, pi * 2,
          _rotationMatrix(progress * pi * 2 * 0.7, rect.center),
        );
        paint.shader = sweep;
        paint.strokeWidth = 2.0 + breathe;
        canvas.drawRRect(rrect, paint);
        break;

      case _ParticleType.bokeh:
        // Warm rotating gradient — dominant/vibrant blend
        final sweep = ui.Gradient.sweep(
          rect.center,
          [
            dominant.withValues(alpha: 0.5 + breathe * 0.3),
            vibrant.withValues(alpha: 0.3),
            accent.withValues(alpha: 0.5 + breathe * 0.2),
            dominant.withValues(alpha: 0.3),
            dominant.withValues(alpha: 0.5 + breathe * 0.3),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
          TileMode.clamp,
          0.0, pi * 2,
          _rotationMatrix(progress * pi * 2 * 0.4, rect.center), // very slow
        );
        paint.shader = sweep;
        paint.strokeWidth = 1.5 + breathe * 0.5;
        canvas.drawRRect(rrect, paint);
        break;

      case _ParticleType.dust:
        // Simple breathing dominant border
        paint
          ..color = dominant.withValues(alpha: 0.25 + breathe * 0.35)
          ..strokeWidth = 1.5 + breathe * 0.5;
        canvas.drawRRect(rrect, paint);
        break;
    }
  }

  Float64List _rotationMatrix(double angle, Offset center) {
    final cosA = cos(angle);
    final sinA = sin(angle);
    return Float64List.fromList([
      cosA, -sinA, 0, 0,
      sinA, cosA, 0, 0,
      0, 0, 1, 0,
      center.dx * (1 - cosA) + center.dy * sinA,
      center.dy * (1 - cosA) - center.dx * sinA,
      0, 1,
    ]);
  }

  @override
  bool shouldRepaint(covariant _PosterBorderPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ATMOSPHERE MIXIN — add to any details screen state
// ═══════════════════════════════════════════════════════════════════════════════

/// Helper to build the full atmosphere backdrop (Ken Burns + particles + tint).
/// Call [loadAtmosphere] in initState after _movie is set.
mixin AtmosphereMixin<T extends StatefulWidget> on State<T> {
  AtmosphereColors? atmosphereColors;

  Future<void> loadAtmosphere(String imageUrl) async {
    final colors = await extractAtmosphereColors(imageUrl);
    if (mounted) {
      setState(() => atmosphereColors = colors);
    }
  }

  /// Build the full atmosphere backdrop layer for a Stack.
  Widget buildAtmosphereBackdrop({
    required String imageUrl,
    required List<String> genres,
    double blurSigma = 28,
  }) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          KenBurnsBackdrop(
            imageUrl: imageUrl,
            colors: atmosphereColors,
            blurSigma: blurSigma,
          ),
          IgnorePointer(
            child: GenreParticles(
              genres: genres,
              colors: atmosphereColors,
            ),
          ),
        ],
      ),
    );
  }

  /// Wrap a poster widget with the breathing glow + genre border.
  Widget wrapPosterGlow({
    required Widget child,
    required double width,
    required double height,
    double borderRadius = 12,
    List<String> genres = const [],
  }) {
    return PosterGlow(
      colors: atmosphereColors,
      genres: genres,
      width: width,
      height: height,
      borderRadius: borderRadius,
      child: child,
    );
  }
}
