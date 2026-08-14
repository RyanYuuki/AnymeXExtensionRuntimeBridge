import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import '../../Services/Aniyomi/Models/Source.dart';
import '../../Services/AniyomiDesktop/DesktopAniyomiExtensions.dart';
import '../../Services/AniyomiDesktop/DesktopAniyomiSourceMethods.dart';
import '../../Services/CloudStream/Models/CloudStreamSource.dart';
import '../../Services/CloudStreamDesktop/DesktopCloudStreamExtensions.dart';
import '../../Services/CloudStreamDesktop/DesktopCloudStreamSourceMethods.dart';
import '../../Services/Kotatsu/Models/Source.dart';
import '../../Services/KotatsuDesktop/DesktopKotatsuExtensions.dart';
import '../../Services/KotatsuDesktop/DesktopKotatsuSourceMethods.dart';

// ─── SSH Transport ──────────────────────────────────────────

/// SSH-based bridge that connects to a remote AnymeX server.
///
/// All method calls (JAR proxy + management) go through SSH exec.
/// The server forwards unknown methods to its local JAR sidecar.
class ServerBridge {
  static const defaultHost = 'anymex.duckdns.org';
  static const defaultPort = 3022;
  static const defaultHttpPort = 8082;

  static final ServerBridge _instance = ServerBridge._internal();
  factory ServerBridge() => _instance;
  ServerBridge._internal();

  SSHClient? _client;
  bool _initialized = false;
  String? _host;
  int _port = defaultPort;
  int _requestId = 0;

  /// Connect to the server via SSH and authenticate.
  /// [host] and [port] default to the production server.
  Future<void> initialize({
    String? host,
    int? port,
    required String username,
    required String password,
  }) async {
    if (_initialized) return;

    _host = host ?? defaultHost;
    _port = port ?? defaultPort;

    final pwd = password;
    final socket = await SSHSocket.connect(_host!, _port);
    _client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => pwd,
    );
    await _client!.authenticated;
    _initialized = true;
    Logger.log('[ServerBridge] Connected to ${_host!}:$_port as $username');
  }

  /// Send a method call through SSH exec and return the result.
  /// Follows the same {method, args, id} → {id, status, data} protocol
  /// as SidecarBridge, but over SSH.
  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!_initialized || _client == null) {
      throw StateError(
          'ServerBridge is not initialized. Call initialize() first.');
    }

    final id = (_requestId++).toString();
    final payload = jsonEncode({
      'method': method,
      'args': args,
      'id': id,
    });

    try {
      final session = await _client!.execute(payload).timeout(timeout);

      final stdoutChunks = <String>[];
      final stderrChunks = <String>[];

      await for (final chunk in session.stdout) {
        stdoutChunks.add(utf8.decode(chunk));
      }
      await for (final chunk in session.stderr) {
        stderrChunks.add(utf8.decode(chunk));
      }

      final output = stdoutChunks.join('').trim();

      if (output.isEmpty) {
        final err = stderrChunks.join('').trim();
        throw Exception(
            err.isNotEmpty ? 'Server error: $err' : 'Empty response from server');
      }

      final response = jsonDecode(output);

      if (response['status'] == 'error') {
        throw Exception(response['error'] ?? 'Unknown server error');
      }

      return response['data'];
    } on TimeoutException {
      throw TimeoutException(
        'Server request "$method" (id: $id) timed out after ${timeout.inSeconds}s',
        timeout,
      );
    } on FormatException {
      throw Exception('Invalid JSON response from server');
    }
  }

  /// SSH exec is one-shot — streaming not natively supported.
  /// Falls back to a single invokeMethod call.
  Stream<dynamic> invokeStreamMethod(
      String method, Map<String, dynamic> args) async* {
    // SSH exec is one-shot — flatten list results into individual stream events.
    final result = await invokeMethod(method, args);
    if (result is List) {
      yield* Stream.fromIterable(result);
    } else {
      yield result;
    }
  }

  void dispose() {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _initialized = false;
    Logger.log('[ServerBridge] Disconnected');
  }

  Future<bool> cancelRequest(String id) async {
    // SSH exec is one-shot — nothing to cancel.
    return false;
  }

  bool get isInitialized => _initialized;
  String? get host => _host;
  int get port => _port;
}

// ─── Server Auth (HTTP) ─────────────────────────────────────

/// Handles user registration and health checks against the server's
/// HTTP endpoint (port 8082). Login is implicit via SSH connect.
class ServerAuth {
  /// Register a new user account on the server.
  /// [host] and [httpPort] default to the production server.
  static Future<Map<String, dynamic>> register({
    String? host,
    int? httpPort,
    required String username,
    required String password,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: host ?? ServerBridge.defaultHost,
      port: httpPort ?? ServerBridge.defaultHttpPort,
      path: '/register',
    );
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Check server health and JAR readiness.
  /// [host] and [httpPort] default to the production server.
  static Future<Map<String, dynamic>> health({
    String? host,
    int? httpPort,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: host ?? ServerBridge.defaultHost,
      port: httpPort ?? ServerBridge.defaultHttpPort,
      path: '/health',
    );
    final res = await http.get(uri);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

// ─── Server Bridge Extensions (v2: extend desktop, override install/uninstall) ──
///
/// Reuses ALL desktop logic: repo fetching, index parsing, dedup, grouping.
/// Only overrides installSource/uninstallSource to go through SSH to server.
/// loadExtensions calls go through BridgeDispatcher → SSH → server → JAR
/// (server intercepts and filters to user's installed extensions).

class ServerAniyomiBridge extends DesktopAniyomiExtensions {
  @override
  bool get requiresPlugin => false;

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    final aSource = source as ASource;
    final url = aSource.apkUrl;
    if (url == null || url.isEmpty) {
      throw Exception('No download URL available for ${aSource.name}');
    }
    await ServerBridge().invokeMethod('installExtension', {
      'url': url,
      'pkgName': aSource.pkgName ?? '',
      'type': 'aniyomi',
      'name': aSource.name,
      'iconUrl': aSource.iconUrl,
      'version': aSource.hasUpdate == true
          ? aSource.versionLast
          : aSource.version,
    });
    // Save metadata locally (same as desktop)
    final pkgName = aSource.pkgName ??
        aSource.apkName?.replaceAll('.apk', '') ?? 'unknown';
    if (aSource.iconUrl != null) {
      setVal('desktop_ext_icon_$pkgName', aSource.iconUrl);
    }
    final versionToSave = aSource.hasUpdate == true
        ? aSource.versionLast
        : aSource.version;
    if (versionToSave != null) {
      setVal('desktop_ext_version_$pkgName', versionToSave);
    }
    if (aSource.itemType == ItemType.anime) {
      await fetchInstalledAnimeExtensions();
    } else {
      await fetchInstalledMangaExtensions();
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;
    final pkgName = s.pkgName;
    if (pkgName == null || pkgName.isEmpty) {
      throw Exception('Source pkgName required');
    }
    await ServerBridge().invokeMethod('uninstallExtension', {
      'pkgName': pkgName,
      'type': 'aniyomi',
    });
    KvStore.remove('desktop_ext_icon_$pkgName');
    KvStore.remove('desktop_ext_version_$pkgName');
    if (s.itemType == ItemType.anime) {
      await fetchInstalledAnimeExtensions();
    } else {
      await fetchInstalledMangaExtensions();
    }
  }
}

class ServerCloudStreamBridge extends DesktopCloudStreamExtensions {
  @override
  bool get requiresPlugin => false;

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    final cs = source as CloudStreamSource;
    final url = cs.pluginUrl ?? cs.jarUrl;
    if (url == null || url.isEmpty) {
      throw Exception('No download URL available for ${cs.name}');
    }
    await ServerBridge().invokeMethod('installExtension', {
      'url': url,
      'pkgName': cs.internalName ?? cs.name ?? '',
      'type': 'cloudstream',
      'name': cs.name,
      'iconUrl': cs.iconUrl,
      'version': cs.version,
    });
    if (cs.itemType == ItemType.anime) {
      await fetchInstalledAnimeExtensions();
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final cs = source as CloudStreamSource;
    await ServerBridge().invokeMethod('uninstallExtension', {
      'pkgName': cs.internalName ?? cs.name ?? '',
      'type': 'cloudstream',
    });
    await fetchInstalledAnimeExtensions();
  }
}

class ServerKotatsuBridge extends DesktopKotatsuExtensions {
  @override
  bool get requiresPlugin => false;

  // Kotatsu install/uninstall is client-side toggle (same as desktop).
  // No server interaction needed for install/uninstall.
  // Only ensureKotatsuJar needs server (handled by overriding fetchInstalledMangaExtensions).

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    try {
      // Ensure server has the Kotatsu JAR downloaded.
      // Repos are in KvStore under '$id${ItemType.manga.name}Repos'.
      final key = '${'kotatsu-desktop'}${ItemType.manga.name}Repos';
      final encoded = getVal<List<String>>(key);
      if (encoded != null && encoded.isNotEmpty) {
        final repos = encoded
            .map((e) => Repo.fromJson(jsonDecode(e)))
            .toList();
        try {
          await ServerBridge()
              .invokeMethod('ensureKotatsuJar', {'url': repos.first.url});
        } catch (e) {
          Logger.log('[ServerKotatsu] Failed to ensure JAR: $e');
        }
      }
      // Let parent handle the rest — kotatsuLoadExtensions goes through
      // SSH → server → JAR (server doesn't filter Kotatsu).
      await super.fetchInstalledMangaExtensions();
    } catch (e, s) {
      Logger.log('[ServerKotatsu] Failed to fetch installed: $e\n$s');
      getInstalledRx(ItemType.manga).value = [];
    }
  }
}
