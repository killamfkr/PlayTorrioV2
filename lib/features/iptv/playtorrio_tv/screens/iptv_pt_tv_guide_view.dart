import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controller/iptv_controller.dart';
import '../data/iptv_network.dart';
import '../data/models.dart';
import 'iptv_pt_player_screen.dart';

/// App bar styled like PT IPTV (`iptv_pt_screen` keeps [_PtAppBar] library-private).
class _GuideScreenAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const _GuideScreenAppBar({
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bebasNeue(
                    color: Colors.white,
                    fontSize: 28,
                    letterSpacing: 1.6,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// TV guide for **starred Live TV channels** across all verified portals (PT IPTV favorites).
class IptvPtTvGuideView extends StatelessWidget {
  final IptvController ctrl;
  final bool compact;
  final bool showBack;

  const IptvPtTvGuideView({
    super.key,
    required this.ctrl,
    required this.compact,
    this.showBack = true,
  });

  String _fmtRange(EpgEntry e) {
    final a =
        '${e.start.hour.toString().padLeft(2, '0')}:${e.start.minute.toString().padLeft(2, '0')}';
    final b =
        '${e.stop.hour.toString().padLeft(2, '0')}:${e.stop.minute.toString().padLeft(2, '0')}';
    return '$a–$b';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _GuideScreenAppBar(
            title: 'Favorite TV Guide',
            subtitle: ctrl.tvGuideLoading
                ? 'Loading…'
                : (ctrl.tvGuideSlots.isEmpty
                    ? 'Star channels in PT IPTV → portal → Live TV'
                    : '${ctrl.tvGuideSlots.length} channels'),
            onBack: showBack ? ctrl.back : null,
            actions: [
              IconButton(
                tooltip: 'Refresh guide',
                onPressed:
                    ctrl.tvGuideLoading ? null : () => ctrl.refreshTvGuide(),
                icon: Icon(
                  Icons.refresh_rounded,
                  color: ctrl.tvGuideLoading ? Colors.white24 : Colors.white70,
                ),
              ),
            ],
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (ctrl.tvGuideError != null && ctrl.tvGuideError!.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ctrl.tvGuideError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }
    if (ctrl.tvGuideLoading && ctrl.tvGuideSlots.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00E5FF),
          strokeWidth: 2,
        ),
      );
    }
    if (ctrl.tvGuideSlots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_outline_rounded,
                  size: 56, color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text(
                'No favorite channels yet',
                style: GoogleFonts.bebasNeue(
                  color: Colors.white,
                  fontSize: 28,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a portal → Live TV and tap the star on channels you want here. '
                'Requires Xtream EPG on your panel.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 16),
      itemCount: ctrl.tvGuideSlots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final slot = ctrl.tvGuideSlots[i];
        return _GuideChannelTile(
          ctrl: ctrl,
          slot: slot,
          compact: compact,
          fmtRange: _fmtRange,
        );
      },
    );
  }
}

class _GuideChannelTile extends StatelessWidget {
  final IptvController ctrl;
  final TvGuideSlot slot;
  final bool compact;
  final String Function(EpgEntry) fmtRange;

  const _GuideChannelTile({
    required this.ctrl,
    required this.slot,
    required this.compact,
    required this.fmtRange,
  });

  void _play(BuildContext context) {
    final url = IptvClient.streamUrl(slot.portal.portal, slot.stream);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IptvPtPlayerScreen.singleStream(
          url: url,
          stream: slot.stream,
          portalName: slot.portal.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _play(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<EpgEntry>>(
            future: ctrl.epgForSlot(slot),
            builder: (_, snap) {
              final pgms = snap.data ?? const <EpgEntry>[];
              EpgEntry? now;
              for (final e in pgms) {
                if (e.isNow) {
                  now = e;
                  break;
                }
              }
              now ??= pgms.isNotEmpty ? pgms.first : null;
              final rest = pgms
                  .where((e) =>
                      now == null ||
                      !(e.start == now.start && e.stop == now.stop))
                  .take(4)
                  .toList();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: slot.stream.icon.isNotEmpty
                        ? Image.network(
                            slot.stream.icon,
                            width: compact ? 52 : 64,
                            height: compact ? 52 : 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholderIcon(),
                          )
                        : SizedBox(
                            width: compact ? 52 : 64,
                            height: compact ? 52 : 64,
                            child: _placeholderIcon(),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                slot.stream.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: compact ? 13 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: 'Remove from favorites',
                              onPressed: () => ctrl.unfavoriteTvGuideSlot(slot),
                              icon: Icon(
                                Icons.star_rounded,
                                color: Colors.amber.withValues(alpha: 0.9),
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          slot.portal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        if (snap.connectionState != ConnectionState.done &&
                            pgms.isEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              color: const Color(0xFF00E5FF),
                            ),
                          ),
                        ],
                        if (now != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: now.isNow
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF00E5FF)
                                          .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  now.isNow ? 'NOW' : 'NEXT',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fmtRange(now),
                                      style: GoogleFonts.poppins(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      now.title.isEmpty ? '—' : now.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (rest.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...rest.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 92,
                                    child: Text(
                                      fmtRange(e),
                                      style: GoogleFonts.poppins(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      e.title.isEmpty ? '—' : e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (snap.connectionState == ConnectionState.done &&
                            pgms.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'No EPG from panel for this channel.',
                            style: GoogleFonts.poppins(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Icon(
        Icons.tv_rounded,
        color: Colors.white.withValues(alpha: 0.25),
        size: 28,
      ),
    );
  }
}
