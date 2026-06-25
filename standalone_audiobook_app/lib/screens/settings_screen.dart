import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/settings_service.dart';
import '../services/playtorrio_cloud_sync_service.dart';
import '../utils/app_theme.dart';
import '../widgets/literary_character_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = true;
  bool _sessionPresent = false;
  bool _syncEnabled = true;
  bool _configured = false;
  bool _signingIn = false;
  bool _registering = false;
  bool _syncing = false;
  String? _signedInEmail;
  int _avatarIndex = 0;
  String _torrentCacheType = 'ram';
  int _torrentRamCacheMb = 200;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cloud = PlaytorrioCloudSyncService.instance;
    final session = await cloud.hasStoredSession();
    final sync = await cloud.isSettingsSyncEnabled();
    final email = await cloud.signedInEmail();
    final cacheType = await _settings.getTorrentCacheType();
    final cacheMb = await _settings.getTorrentRamCacheMb();
    final avatar = await _settings.getUserAvatarIndex();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sessionPresent = session;
      _syncEnabled = sync;
      _configured = cloud.isConfigured;
      _signedInEmail = email;
      _avatarIndex = avatar;
      _torrentCacheType = cacheType;
      _torrentRamCacheMb = cacheMb;
    });
  }

  Future<void> _selectAvatar(int index) async {
    if (index == _avatarIndex) return;
    await _settings.setUserAvatarIndex(index);
    if (!mounted) return;
    setState(() => _avatarIndex = index);
    if (_sessionPresent && _syncEnabled) {
      PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
    }
  }

  Widget _avatarPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Pick a literary character for your profile. These are original cartoon designs inspired by classic book heroes.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: kLiteraryAvatars.length,
            itemBuilder: (context, i) {
              final info = kLiteraryAvatars[i];
              final selected = i == _avatarIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _selectAvatar(i),
                child: Column(
                  children: [
                    LiteraryCharacterAvatar(
                      index: i,
                      size: 58,
                      selected: selected,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? AppTheme.primaryColor : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor),
        ),
      );

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Text(title.toUpperCase(), style: AppTheme.sectionTitle),
          ),
          child,
        ],
      ),
    );
  }

  Widget _syncToggle() {
    return SwitchListTile(
      title: const Text('Sync bookmarks, favorites & progress'),
      subtitle: const Text(
        'Keeps continue listening, liked titles, and bookmarks in sync across devices.',
        style: TextStyle(fontSize: 13, height: 1.35),
      ),
      value: _syncEnabled,
      activeThumbColor: AppTheme.primaryColor,
      onChanged: (v) async {
        await PlaytorrioCloudSyncService.instance.setSettingsSyncEnabled(v);
        if (mounted) setState(() => _syncEnabled = v);
      },
    );
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _snack('Enter your email and password');
      return;
    }
    if (!_configured) {
      _snack('Cloud sync is not configured in this build.');
      return;
    }
    setState(() => _signingIn = true);
    try {
      await PlaytorrioCloudSyncService.instance.signInWithPassword(
        email: email,
        password: password,
      );
      await PlaytorrioCloudSyncService.instance.syncAfterLogin();
      if (!mounted) return;
      setState(() {
        _sessionPresent = true;
        _signedInEmail = email;
        _signingIn = false;
      });
      _passwordController.clear();
      _snack('Signed in — your library is syncing');
    } on PlaytorrioCloudException catch (e) {
      if (mounted) setState(() => _signingIn = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _signingIn = false);
      _snack('Sign in failed: $e');
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 6) {
      _snack('Use a valid email and password (6+ characters)');
      return;
    }
    if (!_configured) {
      _snack('Cloud sync is not configured in this build.');
      return;
    }
    setState(() => _registering = true);
    try {
      await PlaytorrioCloudSyncService.instance.signUpWithPassword(
        email: email,
        password: password,
      );
      await PlaytorrioCloudSyncService.instance.syncAfterLogin();
      if (!mounted) return;
      setState(() {
        _sessionPresent = true;
        _signedInEmail = email;
        _registering = false;
      });
      _passwordController.clear();
      _snack('Account created — your library is syncing');
    } on PlaytorrioCloudException catch (e) {
      if (mounted) setState(() => _registering = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _registering = false);
      _snack('Create account failed: $e');
    }
  }

  Future<void> _signOut() async {
    await PlaytorrioCloudSyncService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _sessionPresent = false;
      _signedInEmail = null;
    });
    _passwordController.clear();
    _snack('Signed out on this device');
  }

  Future<void> _syncNow() async {
    if (!_sessionPresent) return;
    setState(() => _syncing = true);
    try {
      await PlaytorrioCloudSyncService.instance.pullUserSettings();
      await PlaytorrioCloudSyncService.instance.pushUserSettings();
      if (mounted) _snack('Synced with the cloud');
    } catch (e) {
      if (mounted) _snack('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _sectionCard(
                  title: 'Your character',
                  child: _avatarPicker(),
                ),
                if (kIsWeb)
                  _sectionCard(
                    title: 'Account',
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Cloud sync is not available in the web build.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  _sectionCard(
                    title: 'Account',
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              _configured
                                  ? 'Sign in with email to keep bookmarks, favorites, and listening progress on every device. '
                                      'Use the same account as PlayTorrio, or create a new one.'
                                  : 'This build has no cloud URL/key configured.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    height: 1.4,
                                  ),
                            ),
                          ),
                          if (_sessionPresent) ...[
                            const SizedBox(height: 12),
                            ListTile(
                              leading: LiteraryCharacterAvatar(
                                index: _avatarIndex,
                                size: 48,
                                selected: true,
                              ),
                              title: Text(
                                kLiteraryAvatars[clampLiteraryAvatarIndex(_avatarIndex)].label,
                              ),
                              subtitle: Text(
                                _signedInEmail ?? 'Signed in',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _syncToggle(),
                          if (!_sessionPresent) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: _fieldDecoration('Email'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: _fieldDecoration('Password'),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _signingIn ? null : _signIn,
                                    icon: _signingIn
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTheme.bgDark,
                                            ),
                                          )
                                        : const Icon(Icons.login),
                                    label: Text(_signingIn ? 'Signing in…' : 'Sign in'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _registering ? null : _register,
                                    child: Text(
                                      _registering ? 'Creating…' : 'Create account',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            TextButton(
                              onPressed: _signOut,
                              child: const Text('Sign out on this device'),
                            ),
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed: (!_syncEnabled || _syncing) ? null : _syncNow,
                              icon: _syncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_sync_outlined),
                              label: Text(_syncing ? 'Syncing…' : 'Sync now'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                _sectionCard(
                  title: 'Playback',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Torrent cache'),
                          subtitle: const Text(
                            'RAM is faster; disk uses less memory on low-RAM devices.',
                          ),
                          trailing: DropdownButton<String>(
                            value: _torrentCacheType,
                            underline: const SizedBox.shrink(),
                            dropdownColor: AppTheme.bgCard,
                            items: const [
                              DropdownMenuItem(value: 'ram', child: Text('RAM')),
                              DropdownMenuItem(value: 'disk', child: Text('Disk')),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              await _settings.setTorrentCacheType(v);
                              if (mounted) setState(() => _torrentCacheType = v);
                            },
                          ),
                        ),
                        if (_torrentCacheType == 'ram')
                          ListTile(
                            title: const Text('RAM cache size'),
                            subtitle: Text('$_torrentRamCacheMb MB'),
                            trailing: SizedBox(
                              width: 160,
                              child: Slider(
                                value: _torrentRamCacheMb.toDouble(),
                                min: 64,
                                max: 512,
                                divisions: 7,
                                label: '$_torrentRamCacheMb MB',
                                onChanged: (v) async {
                                  final mb = v.round();
                                  await _settings.setTorrentRamCacheMb(mb);
                                  if (mounted) setState(() => _torrentRamCacheMb = mb);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _sectionCard(
                  title: 'About',
                  child: const ListTile(
                    title: Text('Stories'),
                    subtitle: Text(
                      'Audiobook player with Audiobook Bay catalog, torrent playback, and cloud library sync.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
