import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/iptv_service.dart';
import '../models/iptv_credential.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import 'shows_screen.dart';

class IptvHomeScreen extends StatefulWidget {
  const IptvHomeScreen({super.key});

  @override
  State<IptvHomeScreen> createState() => _IptvHomeScreenState();
}

class _IptvHomeScreenState extends State<IptvHomeScreen> {
  final _iptvService = IptvService();

  @override
  void initState() {
    super.initState();
    _iptvService.refreshUserInfo().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout from IPTV?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _iptvService.logout();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userInfo = _iptvService.userInfo;
    final credential = _iptvService.credential;
    final isM3u = credential?.type == IptvLoginType.m3u;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1B2A), Color(0xFF0A0A0F)],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MY IPTV',
                      style: GoogleFonts.bebasNeue(fontSize: 28, color: Colors.white, letterSpacing: 4),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white54, size: 22),
                      tooltip: 'Logout',
                      onPressed: () => _logout(),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Main navigation row: Live TV (big, left) | Movies + Shows (stacked, right)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LIVE TV - tall vertical button on the left
                            Expanded(
                              flex: 5,
                              child: _HomeCard(
                                title: 'LIVE TV',
                                subtitle: 'Watch Live Channels',
                                icon: Icons.live_tv,
                                gradientColors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                                shadowColor: const Color(0xFF1565C0),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IptvLiveScreen())),
                                vertical: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // MOVIES + TV SHOWS stacked vertically on the right
                            Expanded(
                              flex: 7,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _HomeCard(
                                      title: 'MOVIES',
                                      subtitle: 'VOD Library',
                                      icon: Icons.movie_outlined,
                                      gradientColors: const [Color(0xFFB71C1C), Color(0xFFE65100)],
                                      shadowColor: const Color(0xFFB71C1C),
                                      horizontal: true,
                                      onTap: isM3u
                                          ? null
                                          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IptvMoviesScreen())),
                                      disabled: isM3u,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: _HomeCard(
                                      title: 'TV SHOWS',
                                      subtitle: 'Series',
                                      icon: Icons.tv,
                                      gradientColors: const [Color(0xFF4A148C), Color(0xFF880E4F)],
                                      shadowColor: const Color(0xFF4A148C),
                                      horizontal: true,
                                      onTap: isM3u
                                          ? null
                                          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IptvShowsScreen())),
                                      disabled: isM3u,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // User info card pinned at the bottom
                      _buildUserInfoCard(userInfo, credential),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(dynamic userInfo, dynamic credential) {
    final isM3u = credential?.type == IptvLoginType.m3u;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: isM3u
          ? Row(
              children: [
                const Icon(Icons.playlist_play, color: Color(0xFF00E5FF), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('M3U Playlist', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        credential?.m3uUrl ?? '',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _infoRow(Icons.person_outline, 'Username', userInfo?.username ?? 'N/A'),
                const SizedBox(height: 10),
                _infoRow(
                  Icons.verified_user_outlined,
                  'Status',
                  userInfo?.status ?? 'Unknown',
                  valueColor: _statusColor(userInfo?.status),
                ),
                const SizedBox(height: 10),
                _infoRow(Icons.calendar_today_outlined, 'Expires', userInfo?.expiryString ?? 'N/A'),
                const SizedBox(height: 10),
                _infoRow(Icons.cable_outlined, 'Max Connections', '${userInfo?.maxConnections ?? 'N/A'}'),
                if (userInfo?.isTrial == true) ...[
                  const SizedBox(height: 10),
                  _infoRow(Icons.science_outlined, 'Account Type', 'TRIAL', valueColor: Colors.orangeAccent),
                ],
              ],
            ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white38),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
        const Spacer(),
        Container(
          padding: valueColor != null ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3) : EdgeInsets.zero,
          decoration: valueColor != null
              ? BoxDecoration(
                  color: valueColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Text(
            value,
            style: GoogleFonts.poppins(
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.greenAccent;
      case 'expired':
        return Colors.redAccent;
      case 'disabled':
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
  }
}

class _HomeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final Color shadowColor;
  final VoidCallback? onTap;
  final bool disabled;
  final bool vertical;
  final bool horizontal;

  const _HomeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.shadowColor,
    this.onTap,
    this.disabled = false,
    this.vertical = false,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: disabled
              ? [Colors.grey[800]!, Colors.grey[900]!]
              : gradientColors,
        ),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: shadowColor.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(horizontal ? 14 : 20),
            child: horizontal ? _buildHorizontalContent() : _buildVerticalContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: vertical ? 48 : 36, color: disabled ? Colors.white30 : Colors.white),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.bebasNeue(
            fontSize: vertical ? 28 : 22,
            color: disabled ? Colors.white30 : Colors.white,
            letterSpacing: 2,
          ),
        ),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: disabled ? Colors.white24 : Colors.white70,
            fontSize: 12,
          ),
        ),
        if (disabled) ...[
          const SizedBox(height: 4),
          Text(
            'Xtream only',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _buildHorizontalContent() {
    return Row(
      children: [
        Icon(icon, size: 30, color: disabled ? Colors.white30 : Colors.white),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: GoogleFonts.bebasNeue(
                  fontSize: 20,
                  color: disabled ? Colors.white30 : Colors.white,
                  letterSpacing: 2,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: disabled ? Colors.white24 : Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (disabled)
          Text(
            'Xtream only',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10, fontStyle: FontStyle.italic),
          )
        else
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4), size: 22),
      ],
    );
  }
}
