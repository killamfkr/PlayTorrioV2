import 'package:flutter/material.dart';
import 'utils.dart'; // Ensure formatDuration is available
import '../../widgets/tv_interactive.dart';

class PlayerIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;

  const PlayerIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44.0,
    this.iconSize = 22.0,
    this.backgroundColor = const Color(0xA61A1A1A), // 0xFF1A1A1A with 0.65 opacity
    this.iconColor = const Color(0xEBEBEBEB), // White with 0.92 opacity
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        child: TvInkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final bool isBuffering;

  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.isBuffering = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xA61A1A1A),
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        child: TvInkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: isBuffering
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
          ),
        ),
      ),
    );
  }
}

class CustomSeekbar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const CustomSeekbar({
    super.key,
    required this.duration,
    required this.position,
    this.bufferedPosition = Duration.zero,
    this.onSeek,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<CustomSeekbar> createState() => _CustomSeekbarState();
}

class _CustomSeekbarState extends State<CustomSeekbar> {
  bool _isDragging = false;
  double _dragValue = 0.0; // In milliseconds
  
  // Hover state for Desktop
  bool _isHovering = false;
  double _hoverValue = 0.0; // In milliseconds

  @override
  Widget build(BuildContext context) {
    final totalMilliseconds = widget.duration.inMilliseconds.toDouble();
    final currentMilliseconds = widget.position.inMilliseconds.toDouble();
    final bufferedMilliseconds = widget.bufferedPosition.inMilliseconds.toDouble();

    // Avoid division by zero
    final double safeTotal = totalMilliseconds > 0 ? totalMilliseconds : 1.0;

    double relativePosition = (_isDragging ? _dragValue : currentMilliseconds) / safeTotal;
    
    // Clamp
    relativePosition = relativePosition.clamp(0.0, 1.0);

    double bufferedRelative = bufferedMilliseconds / safeTotal;
    bufferedRelative = bufferedRelative.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          onHover: (details) {
            setState(() {
              double dx = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
              _hoverValue = (dx / constraints.maxWidth) * safeTotal;
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() {
                _isDragging = true;
                double dx = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
                _dragValue = (dx / constraints.maxWidth) * safeTotal;
              });
              widget.onDragStart?.call();
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                double dx = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
                _dragValue = (dx / constraints.maxWidth) * safeTotal;
              });
            },
            onHorizontalDragEnd: (details) {
              final seekTo = Duration(milliseconds: _dragValue.toInt());
              setState(() {
                _isDragging = false;
              });
              widget.onSeek?.call(seekTo);
              widget.onDragEnd?.call();
            },
            onTapUp: (details) {
               final dx = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
               final value = (dx / constraints.maxWidth) * safeTotal;
               widget.onSeek?.call(Duration(milliseconds: value.toInt()));
            },
            child: SizedBox(
              height: 30, // Touch target height
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none, // Allow tooltip to overflow upwards
                children: [
                  // Background Track
                  Container(
                    height: 3.0,
                    width: double.infinity,
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                  // Buffered Track
                  FractionallySizedBox(
                    widthFactor: bufferedRelative,
                    child: Container(
                      height: 3.0,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  // Played Track
                  FractionallySizedBox(
                    widthFactor: relativePosition,
                    child: Container(
                      height: 3.0,
                      color: Colors.white,
                    ),
                  ),
                  // Thumb
                  Positioned(
                    left: (relativePosition * constraints.maxWidth) - (_isDragging ? 8.0 : 6.0),
                    child: Container(
                      width: _isDragging ? 16.0 : 12.0,
                      height: _isDragging ? 16.0 : 12.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Tooltip (Hover on Windows, Drag on Mobile/Windows)
                  if (_isDragging || _isHovering)
                    Positioned(
                      left: (_isDragging 
                          ? (relativePosition * constraints.maxWidth) 
                          : (_hoverValue / safeTotal * constraints.maxWidth)) - 24, // Center roughly (assuming width ~48)
                      top: -35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(Duration(milliseconds: _isDragging ? _dragValue.toInt() : _hoverValue.toInt())),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class OverlayGradient extends StatelessWidget {
  final bool isTop;

  const OverlayGradient({super.key, this.isTop = true});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: isTop ? 140 : 140, // Height for gradient area
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: isTop ? 0.75 : 0.80),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

class VolumeBrightnessIndicator extends StatelessWidget {
  final bool isBrightness;
  final double value; // 0.0 to 1.0

  const VolumeBrightnessIndicator({
    super.key,
    required this.isBrightness,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            isBrightness ? Icons.brightness_6_outlined : Icons.volume_up_outlined,
            color: Colors.white,
            size: 20,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: RotatedBox(
                quarterTurns: -1,
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Text(
            "${(value * 100).toInt()}%",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const PillButton({
    super.key,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TvInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xA61A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
