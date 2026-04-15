import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Jellyfin often uses self-signed TLS; accept all certs on IO platforms.
http.Client createJellyfinHttpClient() {
  final ioClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(ioClient);
}
