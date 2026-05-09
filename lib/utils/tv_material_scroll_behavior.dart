import 'package:flutter/material.dart';

/// Android TV: predictable clamped scrolling with the D‑pad / remote.
class TvMaterialScrollBehavior extends MaterialScrollBehavior {
  const TvMaterialScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
