import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal SOCKS5 client (RFC 1928 / 1929) on an already-connected TCP [Socket].
class Socks5Handshake {
  Socks5Handshake._();

  static Future<void> complete(
    Socket socket, {
    required String targetHost,
    required int targetPort,
    String? username,
    String? password,
  }) async {
    if (targetPort <= 0 || targetPort > 65535) {
      throw StateError('Invalid target port');
    }

    final hasUser = username != null && username.isNotEmpty;
    final hasPass = password != null && password.isNotEmpty;
    final useAuth = hasUser && hasPass;

    if (useAuth) {
      socket.add(const [0x05, 0x02, 0x00, 0x02]);
    } else {
      socket.add(const [0x05, 0x01, 0x00]);
    }
    await socket.flush();

    final sel = await _readExact(socket, 2);
    if (sel[0] != 0x05) throw StateError('SOCKS5: bad version');
    if (sel[1] == 0xff) throw StateError('SOCKS5: no acceptable auth method');
    if (sel[1] == 0x02) {
      if (!useAuth) throw StateError('SOCKS5: server requires username/password');
      final u = utf8.encode(username);
      final p = utf8.encode(password);
      if (u.length > 255 || p.length > 255) {
        throw StateError('SOCKS5: username or password too long');
      }
      final auth = BytesBuilder()
        ..addByte(0x01)
        ..addByte(u.length)
        ..add(u)
        ..addByte(p.length)
        ..add(p);
      socket.add(auth.toBytes());
      await socket.flush();
      final ar = await _readExact(socket, 2);
      if (ar[0] != 0x01 || ar[1] != 0x00) {
        throw StateError('SOCKS5: username/password rejected');
      }
    } else if (sel[1] != 0x00) {
      throw StateError('SOCKS5: unexpected auth method ${sel[1]}');
    }

    final ipv4 = InternetAddress.tryParse(targetHost);
    final req = BytesBuilder()
      ..addByte(0x05)
      ..addByte(0x01)
      ..addByte(0x00);

    if (ipv4 != null && ipv4.type == InternetAddressType.IPv4) {
      req
        ..addByte(0x01)
        ..add(ipv4.rawAddress);
    } else if (ipv4 != null && ipv4.type == InternetAddressType.IPv6) {
      req
        ..addByte(0x04)
        ..add(ipv4.rawAddress);
    } else {
      final h = utf8.encode(targetHost);
      if (h.length > 255) throw StateError('SOCKS5: hostname too long');
      req
        ..addByte(0x03)
        ..addByte(h.length)
        ..add(h);
    }
    req
      ..addByte((targetPort >> 8) & 0xff)
      ..addByte(targetPort & 0xff);

    socket.add(req.toBytes());
    await socket.flush();

    final head = await _readExact(socket, 4);
    if (head[0] != 0x05) throw StateError('SOCKS5: bad reply version');
    if (head[1] != 0x00) {
      throw StateError('SOCKS5: connect failed (code ${head[1]})');
    }
    final atyp = head[3];
    var skip = 0;
    if (atyp == 0x01) {
      skip = 4 + 2;
    } else if (atyp == 0x04) {
      skip = 16 + 2;
    } else if (atyp == 0x03) {
      final ln = await _readExact(socket, 1);
      skip = ln[0] + 2;
    } else {
      throw StateError('SOCKS5: unknown address type');
    }
    await _readExact(socket, skip);
  }

  static Future<Uint8List> _readExact(Socket socket, int n) async {
    final buffer = <int>[];
    final completer = Completer<Uint8List>();
    late final StreamSubscription<List<int>> sub;

    sub = socket.listen(
      (data) {
        buffer.addAll(data);
        if (buffer.length >= n && !completer.isCompleted) {
          sub.cancel();
          completer.complete(Uint8List.fromList(buffer.sublist(0, n)));
        }
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: () {
        if (completer.isCompleted) return;
        if (buffer.length >= n) {
          completer.complete(Uint8List.fromList(buffer.sublist(0, n)));
        } else {
          completer.completeError(StateError('SOCKS5: connection closed early'));
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      await sub.cancel();
      rethrow;
    }
  }
}
