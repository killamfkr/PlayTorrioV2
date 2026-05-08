import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Horizontal scrollable strip with overlaid left/right arrow buttons.
/// Arrows appear on desktop/wide screens and on hover; they paginate the
/// list by roughly one viewport width per click. Touch-only / narrow
/// layouts get plain swipe scrolling with no overlay.
class HorizontalScroller extends StatefulWidget {
  final double height;
  final EdgeInsetsGeometry padding;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final double arrowOffset;

  const HorizontalScroller({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding = EdgeInsets.zero,
    this.arrowOffset = 8,
  });

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  final ScrollController _ctrl = ScrollController();
  bool _hovering = false;
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_updateEdges);
    _ctrl.dispose();
    super.dispose();
  }

  void _updateEdges() {
    if (!_ctrl.hasClients) return;
    final left = _ctrl.offset > 4;
    final right = _ctrl.offset < _ctrl.position.maxScrollExtent - 4;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_ctrl.hasClients) return;
    final target = (_ctrl.offset + delta)
        .clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _updateEdges();
                return false;
              },
              child: widget.separatorBuilder != null
                  ? ListView.separated(
                      controller: _ctrl,
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: widget.padding,
                      itemCount: widget.itemCount,
                      separatorBuilder: widget.separatorBuilder!,
                      itemBuilder: widget.itemBuilder,
                    )
                  : ListView.builder(
                      controller: _ctrl,
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: widget.padding,
                      itemCount: widget.itemCount,
                      itemBuilder: widget.itemBuilder,
                    ),
            ),
            if (isDesktop) ...[
              _ArrowButton(
                visible: _hovering && _canLeft,
                left: true,
                offset: widget.arrowOffset,
                onTap: () => _scrollBy(-_pageStep(context)),
              ),
              _ArrowButton(
                visible: _hovering && _canRight,
                left: false,
                offset: widget.arrowOffset,
                onTap: () => _scrollBy(_pageStep(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _pageStep(BuildContext context) {
    // Roughly one viewport's worth, biased a bit smaller so users see overlap.
    final w = MediaQuery.of(context).size.width;
    return (w * 0.7).clamp(280, 1100);
  }
}

class _ArrowButton extends StatelessWidget {
  final bool visible;
  final bool left;
  final double offset;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.visible,
    required this.left,
    required this.offset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? offset : null,
      right: left ? null : offset,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Center(
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              elevation: 6,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    left ? Icons.chevron_left : Icons.chevron_right,
                    color: Colors.white,
                    size: 26,
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
