import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Models/Source.dart';
import '../../Services/Aniyomi/Models/Source.dart';
import '../../Services/AniyomiDesktop/DesktopAniyomiSourceMethods.dart';
import '../../Services/CloudStream/Models/CloudStreamSource.dart';
import '../../Services/CloudStreamDesktop/DesktopCloudStreamSourceMethods.dart';
import '../../Services/Kotatsu/Models/Source.dart';
import '../../Services/KotatsuDesktop/DesktopKotatsuSourceMethods.dart';

// ─── SSH Transport ──────────────────────────────────────────

/// SSH-based bridge that connects to a remote AnymeX server.
///
/// All method calls (JAR proxy + management) go through SSH exec.
/// The server forwards unknown methods to its local JAR sidecar.
class ServerBridge {
  static final ServerBridge _instance = ServerBridge._internal();
  factory ServerBridge() => _instance;
  ServerBridge._internal();

  SSHClient? _client;
  bool _initialized = false;
  String? _host;
  int _port = 3022;
  int _requestId = 0;

  /// Connect to the server via SSH and authenticate.
  Future<void> initialize({
    required String host,
    int port = 3022,
    required String username,
    required String password,
  }) async {
    if (_initialized) return;

    _host = host;
    _port = port;

    final socket = await SSHSocket.connect(host, port);
    _client = SSHClient(
      socket,
      username: username,
      password: password,
    );
    _initialized = true;
    Logger.log('[ServerBridge] Connected to $host:$port as $username');
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
      String method, Map<String, dynamic> args) {
    // Stream controller that does a single invoke and emits the result.
    StreamController<dynamic> controller;
    controller = StreamController<dynamic>(onListen: () async {
      try {
        final result = await invokeMethod(method, args);
        if (result is List) {
          for (final item in result) {
            controller.add(item);
          }
        } else {
          controller.add(result);
        }
      } catch (e) {
        controller.addError(e);
      } finally {
        await controller.close();
      }
    });
    return controller.stream;
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
  static Future<Map<String, dynamic>> register({
    required String host,
    int httpPort = 8082,
    required String username,
    required String password,
  }) async {
    final uri =
        Uri(scheme: 'http', host: host, port: httpPort, path: '/register');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Check server health and JAR readiness.
  static Future<Map<String, dynamic>> health({
    required String host,
    int httpPort = 8082,
  }) async {
    final uri =
        Uri(scheme: 'http', host: host, port: httpPort, path: '/health');
    final res = await http.get(uri);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

// ─── Server Extension Manager ───────────────────────────────

/// Extension manager that uses the remote server for all extension
/// operations (list, install, repos). Runtime calls (getPopular, search,
/// etc.) are forwarded through SSH to the server's JAR sidecar automatically
/// because all SourceMethods call BridgeDispatcher().invokeMethod().
class ServerBridgeExtensions extends Extension {
  /// Maps source ID → server DB extension ID (for install operations).
  final _serverExtIdMap = <String, String>{};

  @override
  String get id => 'server-bridge';

  @override
  String get name => 'Server Bridge';

  @override
  bool get supportsNovel => false;

  @override
  bool get requiresPlugin => false;

  @override
  SourceMethods createSourceMethods(Source source) {
    // All SourceMethods call BridgeDispatcher().invokeMethod() which
    // routes through ServerBridge when bridge type is 'server'.
    // Just need to pick the right SourceMethods class per source type.
    if (source is CloudStreamSource) {
      return DesktopCloudStreamSourceMethods(source);
    }
    if (source is KotatsuSource) {
      return DesktopKotatsuSourceMethods(source);
    }
    return DesktopAniyomiSourceMethods(source);
  }

  /// Override to skip DesktopExtensionBase's local JAR init.
  @override
  Future<void> initialize() async {
    try {
      if (supportsAnime) {
        await fetchInstalledAnimeExtensions();
        unawaited(fetchAnimeExtensions());
      }
      if (supportsManga) {
        await fetchInstalledMangaExtensions();
        unawaited(fetchMangaExtensions());
      }
    } catch (e, s) {
      Logger.log('Error initializing server bridge extensions: $e\n$s');
    }
  }

  // ── Installed Extensions (from server DB via SSH) ──

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    try {
      final result =
          await ServerBridge().invokeMethod('listExtensions', {});
      final list = _parseInstalledList(result as List, ItemType.anime);
      getInstalledRx(ItemType.anime).value = list;

      final available = getRawAvailableRx(ItemType.anime).value;
      if (available.isNotEmpty) {
        _detectUpdates(available, ItemType.anime);
      }
    } catch (e) {
      Logger.log(
          '[ServerBridge] Failed to fetch installed anime extensions: $e');
      getInstalledRx(ItemType.anime).value = [];
    }
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    try {
      final result =
          await ServerBridge().invokeMethod('listExtensions', {});
      final list = _parseInstalledList(result as List, ItemType.manga);
      getInstalledRx(ItemType.manga).value = list;

      final available = getRawAvailableRx(ItemType.manga).value;
      if (available.isNotEmpty) {
        _detectUpdates(available, ItemType.manga);
      }
    } catch (e) {
      Logger.log(
          '[ServerBridge] Failed to fetch installed manga extensions: $e');
      getInstalledRx(ItemType.manga).value = [];
    }
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  List<Source> _parseInstalledList(List result, ItemType filterType) {
    final sources = <Source>[];
    for (final e in result) {
      final map = e as Map<String, dynamic>;
      final serverType = (map['type'] as String?)?.toLowerCase() ?? '';

      // Map server type to ItemType and check if it matches the filter.
      final itemType = _serverTypeToItemType(serverType);
      if (itemType != filterType) continue;

      // Map server type to correct Source subclass.
      sources.add(_mapToSource(map, serverType));
    }
    return sources;
  }

  // ── Available Extensions (from server DB via SSH) ──

  @override
  Future<void> fetchAnimeExtensions() async {
    try {
      final result = await ServerBridge().invokeMethod('getExtensions', {
        'type': 'anime',
      });
      final all = _parseAvailableList(result as List, ItemType.anime);
      getRawAvailableRx(ItemType.anime).value = List.unmodifiable(all);

      final installedIds =
          getInstalledRx(ItemType.anime).value.map((e) => e.id).toSet();
      getAvailableRx(ItemType.anime).value =
          List.unmodifiable(all.where((s) => !installedIds.contains(s.id)));
    } catch (e) {
      Logger.log(
          '[ServerBridge] Failed to fetch available anime extensions: $e');
    }
  }

  @override
  Future<void> fetchMangaExtensions() async {
    try {
      final result = await ServerBridge().invokeMethod('getExtensions', {
        'type': 'manga',
      });
      final all = _parseAvailableList(result as List, ItemType.manga);
      getRawAvailableRx(ItemType.manga).value = List.unmodifiable(all);

      final installedIds =
          getInstalledRx(ItemType.manga).value.map((e) => e.id).toSet();
      getAvailableRx(ItemType.manga).value =
          List.unmodifiable(all.where((s) => !installedIds.contains(s.id)));
    } catch (e) {
      Logger.log(
          '[ServerBridge] Failed to fetch available manga extensions: $e');
    }
  }

  @override
  Future<void> fetchNovelExtensions() async {}

  List<Source> _parseAvailableList(List result, ItemType filterType) {
    final sources = <Source>[];
    for (final e in result) {
      final map = e as Map<String, dynamic>;
      final serverType = (map['type'] as String?)?.toLowerCase() ?? '';

      final itemType = _serverTypeToItemType(serverType);
      if (itemType != filterType) continue;

      sources.add(_mapToSource(map, serverType));
    }
    return sources;
  }

  // ── Install / Uninstall / Update ──

  @override
  Future<void> installSource(Source source) async {
    try {
      final serverExtId = _getServerExtId(source);
      if (serverExtId == null) {
        throw Exception('No server extension ID found for ${source.name}');
      }

      await ServerBridge().invokeMethod('installExtension', {
        'extId': serverExtId,
      });

      // Re-fetch installed list to pick up the newly installed extension.
      if (source.itemType == ItemType.anime) {
        await fetchInstalledAnimeExtensions();
      } else if (source.itemType == ItemType.manga) {
        await fetchInstalledMangaExtensions();
      }

      // Remove from available since it's now installed.
      final avail = getAvailableRx(source.itemType!);
      avail.value = avail.value.where((e) => e.id != source.id).toList();
    } catch (e) {
      Logger.log('[ServerBridge] Failed to install ${source.name}: $e');
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    try {
      final serverExtId = _getServerExtId(source);
      if (serverExtId == null) {
        throw Exception('No server extension ID found for ${source.name}');
      }

      await ServerBridge().invokeMethod('uninstallExtension', {
        'extId': serverExtId,
      });

      // Re-fetch installed list.
      if (source.itemType == ItemType.anime) {
        await fetchInstalledAnimeExtensions();
      } else if (source.itemType == ItemType.manga) {
        await fetchInstalledMangaExtensions();
      }
    } catch (e) {
      Logger.log('[ServerBridge] Failed to uninstall ${source.name}: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  /// Look up the server's DB extension ID for a given source.
  String? _getServerExtId(Source source) {
    return _serverExtIdMap[source.id] ??
        _serverExtIdMap[source.name ?? ''] ??
        _serverExtIdMap[(source is ASource ? source.pkgName : null) ?? ''] ??
        _serverExtIdMap[(source is KotatsuSource ? source.pkgName : null) ?? ''];
  }

  // ── Repos ──

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      await ServerBridge().invokeMethod('addRepo', {
        'url': repoUrl,
        'type': type.name,
      });

      // Re-fetch available extensions after adding repo.
      if (type == ItemType.anime) {
        await fetchAnimeExtensions();
      } else if (type == ItemType.manga) {
        await fetchMangaExtensions();
      }

      await _fetchRepos();
    } catch (e) {
      Logger.log('[ServerBridge] Failed to add repo $repoUrl: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      await ServerBridge().invokeMethod('removeRepo', {
        'url': repoUrl,
      });

      await _fetchRepos();

      // Re-fetch available since removing a repo may affect the list.
      if (type == ItemType.anime) {
        await fetchAnimeExtensions();
      } else if (type == ItemType.manga) {
        await fetchMangaExtensions();
      }
    } catch (e) {
      Logger.log('[ServerBridge] Failed to remove repo $repoUrl: $e');
      rethrow;
    }
  }

  Future<void> _fetchRepos() async {
    try {
      final result = await ServerBridge().invokeMethod('getRepos', {});
      final repos = <Repo>[];
      for (final e in (result as List)) {
        final map = e as Map<String, dynamic>;
        repos.add(Repo(
          url: map['url'] as String? ?? '',
          name: map['name'] as String?,
          managerId: id,
        ));
      }
      for (final type in ItemType.values) {
        getReposRx(type).value = repos;
      }
    } catch (e) {
      Logger.log('[ServerBridge] Failed to fetch repos: $e');
    }
  }

  // ── Update Detection ──

  void _detectUpdates(List<Source> available, ItemType type) {
    final installed = getInstalledRx(type).value;
    if (installed.isEmpty || available.isEmpty) return;

    final repoMap = {for (final s in available) s.id: s};
    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];
      if (repo == null) continue;

      if (compareVersions(repo.version ?? '0', inst.version ?? '0') > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version;
        changed = true;
      }
    }

    if (changed) {
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Set<String> get schemes => const {};

  // ── Type mapping helpers ──

  /// Server stores types as: 'aniyomi-anime', 'aniyomi-manga', 'cloudstream', 'kotatsu'.
  /// Map those to our ItemType enum.
  static ItemType _serverTypeToItemType(String serverType) {
    switch (serverType) {
      case 'aniyomi-anime':
      case 'cloudstream':
        return ItemType.anime;
      case 'aniyomi-manga':
      case 'kotatsu':
        return ItemType.manga;
      default:
        // Fallback: if serverType contains 'anime' or 'manga', use that.
        if (serverType.contains('anime')) return ItemType.anime;
        if (serverType.contains('manga')) return ItemType.manga;
        return ItemType.anime;
    }
  }

  /// Determine the bridge kind from server type string.
  /// Returns: 'aniyomi', 'cloudstream', or 'kotatsu'.
  static String _serverTypeToKind(String serverType) {
    if (serverType.contains('cloudstream')) return 'cloudstream';
    if (serverType.contains('kotatsu')) return 'kotatsu';
    return 'aniyomi';
  }

  /// Create the correct Source subclass based on server data.
  Source _mapToSource(Map<String, dynamic> map, String serverType) {
    final kind = _serverTypeToKind(serverType);
    switch (kind) {
      case 'cloudstream':
        return _mapToCloudStreamSource(map);
      case 'kotatsu':
        return _mapToKotatsuSource(map);
      default:
        return _mapToAniyomiSource(map, serverType);
    }
  }

  ASource _mapToAniyomiSource(Map<String, dynamic> map, String serverType) {
    final serverDbId = map['id']?.toString();
    final sourceId = map['pkg']?.toString() ?? serverDbId ?? '';

    final source = ASource(
      id: sourceId,
      name: map['name'] as String?,
      lang: map['lang'] as String?,
      pkgName: map['pkg'] as String?,
      version: map['version'] as String?,
      isNsfw: map['is_nsfw'] as bool? ?? false,
      baseUrl: map['base_url'] as String?,
      itemType: _serverTypeToItemType(serverType),
      iconUrl: map['icon_url'] as String?,
    );
    source.managerId = id;

    _storeServerExtId(serverDbId, sourceId, source.pkgName, source.name);

    return source;
  }

  CloudStreamSource _mapToCloudStreamSource(Map<String, dynamic> map) {
    final serverDbId = map['id']?.toString();
    final sourceId = map['pkg']?.toString() ?? serverDbId ?? '';

    final source = CloudStreamSource(
      id: sourceId,
      name: map['name'] as String?,
      lang: map['lang'] as String?,
      version: map['version'] as String?,
      isNsfw: map['is_nsfw'] as bool? ?? false,
      baseUrl: map['base_url'] as String?,
      itemType: ItemType.anime,
      iconUrl: map['icon_url'] as String?,
      internalName: map['pkg'] as String?,
    );
    source.managerId = id;

    _storeServerExtId(serverDbId, sourceId, null, source.name);

    return source;
  }

  KotatsuSource _mapToKotatsuSource(Map<String, dynamic> map) {
    final serverDbId = map['id']?.toString();
    final sourceId = map['pkg']?.toString() ?? serverDbId ?? '';

    // Parse extra JSON for additional Kotatsu fields.
    Map<String, dynamic>? extra;
    try {
      final raw = map['extra'];
      if (raw is String) {
        extra = jsonDecode(raw) as Map<String, dynamic>;
      } else if (raw is Map) {
        extra = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    final source = KotatsuSource(
      id: sourceId,
      name: map['name'] as String?,
      lang: map['lang'] as String?,
      version: map['version'] as String?,
      isNsfw: map['is_nsfw'] as bool? ?? false,
      baseUrl: map['base_url'] as String?,
      itemType: ItemType.manga,
      iconUrl: map['icon_url'] as String?,
      pkgName: map['pkg'] as String?,
      jarName: extra?['jarName'] as String?,
    );
    source.managerId = id;

    _storeServerExtId(serverDbId, sourceId, source.pkgName, source.name);

    return source;
  }

  /// Store server DB ID mappings so installSource can look them up.
  void _storeServerExtId(
    String? serverDbId,
    String sourceId,
    String? pkgName,
    String? name,
  ) {
    if (serverDbId == null) return;
    _serverExtIdMap[sourceId] = serverDbId;
    if (pkgName != null) _serverExtIdMap[pkgName] = serverDbId;
    if (name != null) _serverExtIdMap[name] = serverDbId;
  }
}
