import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:visibility_detector/visibility_detector.dart';
import '../models/iptv_credential.dart';
import '../services/iptv_service.dart';
import '../../../utils/iframe_sandbox_strip_js.dart';
import 'iptv_home_screen.dart';

class IptvLoginScreen extends StatefulWidget {
  const IptvLoginScreen({super.key});

  @override
  State<IptvLoginScreen> createState() => _IptvLoginScreenState();
}

class _IptvLoginScreenState extends State<IptvLoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _m3uController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _checkingSession = true;
  bool _useDefault = true;
  bool _sessionChecked = false;
  String? _error;

  final _iptvService = IptvService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Pre-load credential data immediately (fast, no navigation).
    // Auto-navigation to IptvHomeScreen is deferred until the tab
    // is actually visible (handled by VisibilityDetector in build).
    _preloadSession();
  }

  Future<void> _preloadSession() async {
    try {
      await _iptvService.loadSavedCredential();
    } catch (_) {}
    if (mounted) {
      setState(() => _checkingSession = false);
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!_sessionChecked && info.visibleFraction > 0) {
      _sessionChecked = true;
      if (_iptvService.isLoggedIn && mounted) {
        _navigateToHome();
      }
    }
  }

  void _navigateToHome() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IptvHomeScreen()),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_tabController.index == 0) {
        // Xtream
        final server = _serverController.text.trim();
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();

        if (server.isEmpty || username.isEmpty || password.isEmpty) {
          throw Exception('Please fill in all fields');
        }

        await _iptvService.loginXtream(server, username, password);
      } else {
        // M3U
        final url = _m3uController.text.trim();
        if (url.isEmpty) throw Exception('Please enter a playlist URL');
        await _iptvService.loginM3u(url);
      }

      if (mounted) _navigateToHome();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _m3uController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return VisibilityDetector(
        key: const Key('iptv-login-visibility'),
        onVisibilityChanged: (_) {},
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.live_tv, size: 64, color: Color(0xFF00E5FF)),
                const SizedBox(height: 20),
                Text('IPTV', style: GoogleFonts.bebasNeue(fontSize: 32, color: Colors.white, letterSpacing: 4)),
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: Color(0xFF00E5FF)),
              ],
            ),
          ),
        ),
      );
    }

    return VisibilityDetector(
      key: const Key('iptv-login-visibility'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1B2A), Color(0xFF0A0A0F)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Mode toggle (Default / Custom) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    Expanded(child: _buildModeButton('Default', Icons.public, _useDefault, () {
                      if (!_useDefault) setState(() => _useDefault = true);
                    })),
                    const SizedBox(width: 12),
                    Expanded(child: _buildModeButton('Custom', Icons.tune, !_useDefault, () {
                      if (_useDefault) setState(() => _useDefault = false);
                    })),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Content ──
              Expanded(
                child: _useDefault ? _buildDefaultWebView() : _buildCustomLogin(),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildModeButton(String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF0D47A1)])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: selected ? const Color(0xFF1565C0) : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white38, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : Colors.white54,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _defaultIptvUrl = 'https://iptvplaytorrio.pages.dev';

  Widget _buildDefaultWebView() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_defaultIptvUrl)),
        initialUserScripts: iframeSandboxStripUserScripts(),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          supportZoom: false,
          transparentBackground: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          supportMultipleWindows: false,
        ),
        onLoadStop: (controller, url) async {
          await controller.evaluateJavascript(
            source: iframeSandboxStripAtDocumentStartJs(),
          );
        },
        shouldOverrideUrlLoading: (ctrl, action) async {
          final url = action.request.url?.toString() ?? '';
          final embedHost = Uri.tryParse(_defaultIptvUrl)?.host ?? '';
          // Allow all iframe / sub-frame loads (video players, embeds)
          if (!action.isForMainFrame) {
            return NavigationActionPolicy.ALLOW;
          }
          // Allow navigation within the main IPTV domain
          if (url.contains(embedHost)) {
            return NavigationActionPolicy.ALLOW;
          }
          // Main-frame navigation away from our domain = ad click
          // Silently ping the ad URL so the tracker thinks it was opened
          http.get(Uri.parse(url), headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/122.0.0.0 Safari/537.36',
            'Referer': _defaultIptvUrl,
          }).catchError((_) => http.Response('', 200));
          return NavigationActionPolicy.CANCEL;
        },
        onCreateWindow: (controller, createWindowAction) async {
          return false;
        },
      ),
    );
  }

  Widget _buildCustomLogin() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                    // Logo area
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF00E5FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.live_tv, size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'IPTV',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 40,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect your IPTV service',
                      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Tab selector
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF1565C0),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                        tabs: const [
                          Tab(text: 'Xtream Codes'),
                          Tab(text: 'M3U Playlist'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tab content
                    ListenableBuilder(
                      listenable: _tabController,
                      builder: (context, _) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _tabController.index == 0
                              ? _buildXtreamForm()
                              : _buildM3uForm(),
                        );
                      },
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _loading ? null : () => _login(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(
                                  'LOGIN',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // ── Saved Playlists ──
                    if (_iptvService.savedCredentials.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Container(width: 3, height: 18, decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF),
                            borderRadius: BorderRadius.circular(2),
                          )),
                          const SizedBox(width: 10),
                          Text('Saved Playlists', style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._iptvService.savedCredentials.map((cred) {
                        final isActive = _iptvService.credential?.id == cred.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                setState(() => _loading = true);
                                try {
                                  await _iptvService.switchToCredential(cred);
                                  if (mounted) { _navigateToHome(); }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _error = 'Failed to connect: ${e.toString().replaceFirst("Exception: ", "")}';
                                      _loading = false;
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: isActive
                                      ? const Color(0xFF1565C0).withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFF1565C0).withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      cred.type == IptvLoginType.xtream ? Icons.dns_outlined : Icons.playlist_play,
                                      color: isActive ? const Color(0xFF00E5FF) : Colors.white38,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            cred.name,
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            cred.type == IptvLoginType.xtream
                                                ? 'Xtream • ${cred.username}'
                                                : 'M3U Playlist',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.4),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text('Active', style: GoogleFonts.poppins(
                                          color: const Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.w600,
                                        )),
                                      ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: const Color(0xFF1A1A2E),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            title: const Text('Remove Playlist', style: TextStyle(color: Colors.white)),
                                            content: Text('Remove "${cred.name}"?', style: const TextStyle(color: Colors.white70)),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && mounted) {
                                          await _iptvService.removeCredential(cred.id);
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          );
  }

  Widget _buildXtreamForm() {
    return Column(
      key: const ValueKey('xtream'),
      children: [
        _buildTextField(
          controller: _serverController,
          label: 'Server URL',
          hint: 'http://example.com:8080',
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _usernameController,
          label: 'Username',
          hint: 'Enter username',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Enter password',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ],
    );
  }

  Widget _buildM3uForm() {
    return Column(
      key: const ValueKey('m3u'),
      children: [
        _buildTextField(
          controller: _m3uController,
          label: 'Playlist URL',
          hint: 'https://example.com/playlist.m3u',
          icon: Icons.link,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Remote M3U URL or direct stream URL',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
