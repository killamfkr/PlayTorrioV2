import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../utils/tv_guide_refresh.dart';
import '../controller/iptv_controller.dart';
import '../data/iptv_cloud_bundle.dart';
import 'iptv_pt_tv_guide_view.dart';

/// Main-tab wrapper: loads verified portals then builds the favorites TV guide.
class IptvPtTvGuideTabScreen extends StatefulWidget {
  const IptvPtTvGuideTabScreen({super.key});

  @override
  State<IptvPtTvGuideTabScreen> createState() => _IptvPtTvGuideTabScreenState();
}

class _IptvPtTvGuideTabScreenState extends State<IptvPtTvGuideTabScreen> {
  late final IptvController _ctrl;
  VoidCallback? _refreshListener;

  @override
  void initState() {
    super.initState();
    _ctrl = IptvController();
    _refreshListener = () {
      if (!mounted) return;
      unawaited(_reloadGuide());
    };
    TvGuideRefresh.notifier.addListener(_refreshListener!);
    IptvCloudBundle.epoch.addListener(_refreshListener!);
    unawaited(_reloadGuide());
  }

  Future<void> _reloadGuide() async {
    await _ctrl.reloadVerifiedFromDisk();
    if (!mounted) return;
    await _ctrl.refreshTvGuide();
  }

  @override
  void dispose() {
    if (_refreshListener != null) {
      TvGuideRefresh.notifier.removeListener(_refreshListener!);
      IptvCloudBundle.epoch.removeListener(_refreshListener!);
    }
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
