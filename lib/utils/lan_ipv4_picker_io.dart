import 'dart:io';

import 'package:flutter/services.dart';

import 'ipv4_literal.dart';

/// True if [s] is a non-loopback, non-zero IPv4 literal.
bool isValidPublicStyleIpv4(String s) {
  final t = s.trim();
  if (!isIpv4Literal(t)) return false;
  if (t == '0.0.0.0') return false;
  if (t.startsWith('127.')) return false;
  return true;
}

/// Android: same ranking as [MainActivity.preferredLanIpv4] (Kotlin).
Future<String?> androidPreferredLanIpv4FromPlatform() async {
  if (!Platform.isAndroid) return null;
  try {
    const ch = MethodChannel('com.example.play_torrio_native/device');
    final ip = await ch.invokeMethod<String>('getLanIpv4');
    if (ip != null && ip.isNotEmpty && isValidPublicStyleIpv4(ip)) {
      return ip.trim();
    }
  } catch (_) {}
  return null;
}

int _ifaceModifier(String ifaceName) {
  final n = ifaceName.toLowerCase();
  const vpnish = [
    'tailscale',
    'tun',
    'tap',
    'wg',
    'ppp',
    'nordlynx',
    'nordtap',
    'vpn',
    'veth',
    'docker',
    'br-',
    'virbr',
    'zt',
    'hamachi',
    'outline',
    'warp',
    'rndis',
    'ipsec',
    'l2tp',
    'pptp',
  ];
  for (final b in vpnish) {
    if (n.contains(b)) return -8000;
  }
  if (n.contains('wlan') ||
      n.contains('wifi') ||
      n.contains('wlp') ||
      n.contains('wl')) {
    return 80;
  }
  if (n.contains('en') || n.contains('eth') || n.contains('Ethernet')) {
    return 60;
  }
  return 0;
}

/// Prefer typical home LAN subnets over VPN / overlay [10.x] addresses.
int _ipPreferenceScore(String ip) {
  if (ip.startsWith('169.254.')) return -1;
  if (ip.startsWith('192.168.')) return 5000;
  final parts = ip.split('.');
  if (parts.length != 4) return 0;
  final o1 = int.tryParse(parts[0]);
  final o2 = int.tryParse(parts[1]);
  if (o1 == 172 && o2 != null && o2 >= 16 && o2 <= 31) return 4500;
  if (o1 == 172) return 600;
  if (o1 == 10) return 2000;
  if (o1 == 100 && o2 != null && o2 >= 64 && o2 <= 127) return 500;
  return 800;
}

/// Picks the best local IPv4 when multiple interfaces exist (VPN vs Wi‑Fi).
Future<String?> pickBestLanIpv4FromInterfaces() async {
  var bestScore = -999999;
  String? bestIp;
  try {
    final ifaces = await NetworkInterface.list(includeLoopback: false);
    for (final iface in ifaces) {
      final mod = _ifaceModifier(iface.name);
      for (final addr in iface.addresses) {
        if (addr.type != InternetAddressType.IPv4) continue;
        final ip = addr.address;
        final s = _ipPreferenceScore(ip);
        if (s < 0) continue;
        final total = s + mod;
        if (total > bestScore) {
          bestScore = total;
          bestIp = ip;
        }
      }
    }
  } catch (_) {}
  return bestIp;
}

/// [overrideIpv4] is a user-entered address from settings (optional).
Future<String?> resolvePreferredLanIpv4(String? overrideIpv4) async {
  final o = overrideIpv4?.trim();
  if (o != null && o.isNotEmpty && isValidPublicStyleIpv4(o)) {
    return o.trim();
  }
  final fromAndroid = await androidPreferredLanIpv4FromPlatform();
  if (fromAndroid != null) return fromAndroid;
  return pickBestLanIpv4FromInterfaces();
}
