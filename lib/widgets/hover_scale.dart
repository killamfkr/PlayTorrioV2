import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// A small interactive wrapper that scales + glows on mouse hover.
/// Cheap drop-in replacement for `GestureDetector(onTap: …)` on cards.
class HoverScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final double radius;

  const HoverScale({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 1.04,
    this.radius = 14,
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..scaleByDouble(
              _hover ? widget.scale : 1.0,
              _hover ? widget.scale : 1.0,
              1.0,
              1.0,
            ),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
