import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/settings_service.dart';
import '../play_torrio_splash.dart' show SplashScreen;
import '../services/playtorrio_cloud_sync_service.dart';
import '../services/watch_history_service.dart';
import '../utils/app_theme.dart';
import '../utils/device_profile.dart';
import '../widgets/tv_interactive.dart';

const List<IconData> kProfileAvatars = [
  Icons.account_circle,
  Icons.face,
  Icons.sentiment_very_satisfied,
  Icons.pets,
  Icons.sports_soccer,
  Icons.music_note,
  Icons.star,
  Icons.favorite,
];

/// Nuvio-style: sign in (Supabase) + 1..4 profile tiles, then the rest of the app.
class PlaytorrioProfileGate extends StatefulWidget {
  const PlaytorrioProfileGate({super.key, this.child = const SplashScreen()});

  final Widget child;

  @override
  State<PlaytorrioProfileGate> createState() => _PlaytorrioProfileGateState();
}

class _PlaytorrioProfileGateState extends State<PlaytorrioProfileGate> {
  final _settings = SettingsService();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;
  bool _session = false;
  String _editName = '';
  int _editAv = 0;
  late final TextEditingController _editNameCtrl;

  @override
  void initState() {
    super.initState();
    _editNameCtrl = TextEditingController();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (kIsWeb) {
      await WatchHistoryService.ensureProfileFromSettings();
      if (mounted) setState(() => _done = true);
      return;
    }
    if (DeviceProfile.isAndroidTv) {
      await WatchHistoryService.ensureProfileFromSettings();
      if (mounted) setState(() => _done = true);
      return;
    }
    if (!await _settings.getPlaytorrioProfileGateEnabled()) {
      await WatchHistoryService.ensureProfileFromSettings();
      if (mounted) setState(() => _done = true);
      return;
    }
    _session = await PlaytorrioCloudSyncService.instance.hasStoredSession();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _editNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final e = _email.text.trim();
    final p = _pass.text;
    if (e.isEmpty || p.isEmpty) {
      setState(() => _error = 'Email and password required');
      return;
    }
    if (!PlaytorrioCloudSyncService.instance.isConfigured) {
      setState(() => _error = 'Supabase not configured in this build');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaytorrioCloudSyncService.instance.signInWithPassword(
        email: e,
        password: p,
      );
      await PlaytorrioCloudSyncService.instance.pullProfileMeta();
      _pass.clear();
      if (mounted) {
        setState(() {
          _session = true;
          _busy = false;
        });
      }
    } on PlaytorrioCloudException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _signUp() async {
    final e = _email.text.trim();
    final p = _pass.text;
    if (e.isEmpty || p.length < 6) {
      setState(() => _error = 'Valid email and 6+ char password');
      return;
    }
    if (!PlaytorrioCloudSyncService.instance.isConfigured) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaytorrioCloudSyncService.instance.signUpWithPassword(
        email: e,
        password: p,
      );
      _pass.clear();
      await PlaytorrioCloudSyncService.instance.pullProfileMeta();
      if (mounted) {
        setState(() {
          _session = true;
          _busy = false;
        });
      }
    } on PlaytorrioCloudException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await PlaytorrioCloudSyncService.instance.signOut();
    if (mounted) setState(() => _session = false);
  }

  Future<void> _skipGateForever() async {
    await _settings.setPlaytorrioProfileGateEnabled(false);
    final id = await _settings.getPlaytorrioProfileId();
    await _continueWithProfile(id);
  }

  Future<void> _continueWithProfile(int profileId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final id = profileId.clamp(1, 4);
    try {
      await _settings.setPlaytorrioProfileId(id);
      await WatchHistoryService.rebindToProfile(id);
      if (_session && PlaytorrioCloudSyncService.instance.isConfigured) {
        await PlaytorrioCloudSyncService.instance.pullOnStartup();
        await PlaytorrioCloudSyncService.instance.pushFullProfileBackup();
        await PlaytorrioCloudSyncService.instance.pushProfileMetaRow();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
    if (mounted) {
      setState(() {
        _done = true;
        _busy = false;
      });
    }
  }

  void _openEdit(int p) {
    unawaited(_loadEdit(p));
  }

  Future<void> _loadEdit(int p) async {
    final m = await _settings.getLocalProfileDisplayMeta();
    final row = m['$p'] ?? {};
    _editName = (row['name'] as String?)?.trim() ?? 'Profile $p';
    _editAv = (row['avatar'] is int) ? row['avatar'] as int : 0;
    _editNameCtrl.text = _editName;
    if (mounted) setState(() {});

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (c, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(c).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit profile $p',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _editNameCtrl,
                    onChanged: (v) => _editName = v,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: Colors.white38),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: kProfileAvatars.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        return TvGestureTap(
                          onTap: () {
                            setModal(() => _editAv = i);
                            setState(() {});
                          },
                          child: Container(
                            width: 56,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _editAv == i
                                    ? AppTheme.primaryColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              kProfileAvatars[i],
                              size: 36,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () async {
                      final nm = _editNameCtrl.text.trim();
                      await _settings.setLocalProfileDisplayMeta(
                        p,
                        name: nm.isEmpty ? 'Profile $p' : nm,
                        avatarKey: _editAv,
                      );
                      if (_session &&
                          PlaytorrioCloudSyncService.instance.isConfigured) {
                        await PlaytorrioCloudSyncService.instance
                            .pushProfileMetaRow();
                      }
                      if (context.mounted) {
                        Navigator.pop(c);
                        setState(() {});
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    if (kIsWeb || DeviceProfile.isAndroidTv) {
      return widget.child;
    }
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  "Who's watching?",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.bebasNeue(
                    fontSize: 36,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use your Supabase login for cloud backup, or use profiles locally. '
                  'Up to 4 members — like Nuvio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                if (!PlaytorrioCloudSyncService.instance.isConfigured)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Cloud is not configured — profiles and history stay on this device.',
                      style: TextStyle(color: Colors.amber, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (!PlaytorrioCloudSyncService.instance.isAnonKeyJwtFormat)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'This build’s API key is not the Supabase anon JWT. Auth may work, but saving '
                      'watch history to the database will fail. In Supabase: Project → API → '
                      'copy the anon (legacy) key (starts with eyJ…) and set PLAYTORRIO_SUPABASE_ANON_KEY.',
                      style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_session) ...[
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Cloud backup: on (signed in)',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _signOut, child: const Text('Sign out')),
                ] else
                  _authCard(),
                const SizedBox(height: 8),
                FutureBuilder<Map<String, Map<String, dynamic>>>(
                  future: _settings.getLocalProfileDisplayMeta(),
                  builder: (c, snap) {
                    final meta = snap.data ?? {};
                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.9,
                      children: List.generate(4, (i) {
                        final p = i + 1;
                        final av = (meta['$p']?['avatar'] is int)
                            ? meta['$p']!['avatar'] as int
                            : 0;
                        final name = (meta['$p']?['name'] as String?);
                        final label = (name != null && name.isNotEmpty)
                            ? name
                            : 'Profile $p';
                        return Material(
                          color: Colors.transparent,
                          child: TvInkWell(
                            onTap: _busy ? null : () => _continueWithProfile(p),
                            onLongPress: () => _openEdit(p),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: const Color(0xFF1A1A2E),
                                border: Border.all(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    kProfileAvatars[av % kProfileAvatars.length],
                                    size: 48,
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _skipGateForever,
                  child: const Text("Don't show this screen on startup (Settings)"),
                ),
                const SizedBox(height: 4),
                Text(
                  'Long-press a profile to rename and pick an icon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _authCard() {
    return Card(
      color: const Color(0xFF1A1A2E),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.white38),
                filled: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: Colors.white38),
                filled: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: const Text('Sign in'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _signUp,
                    child: const Text('Create account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
