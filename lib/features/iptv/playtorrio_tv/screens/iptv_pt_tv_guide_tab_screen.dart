import 'package:flutter/material.dart';

import '../controller/iptv_controller.dart';
import 'iptv_pt_tv_guide_view.dart';

/// Main-tab wrapper: loads verified portals then builds the favorites TV guide.
class IptvPtTvGuideTabScreen extends StatefulWidget {
  const IptvPtTvGuideTabScreen({super.key});

  @override
  State<IptvPtTvGuideTabScreen> createState() => _IptvPtTvGuideTabScreenState();
}

class _IptvPtTvGuideTabScreenState extends State<IptvPtTvGuideTabScreen> {
  late final IptvController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = IptvController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _ctrl.init();
    if (!mounted) return;
    await _ctrl.refreshTvGuide();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isCompact(BuildContext c) => MediaQuery.sizeOf(c).width < 720;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0F), Color(0xFF0E1428), Color(0xFF06070C)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => IptvPtTvGuideView(
            ctrl: _ctrl,
            compact: _isCompact(context),
            showBack: false,
          ),
        ),
      ),
    );
  }
}
