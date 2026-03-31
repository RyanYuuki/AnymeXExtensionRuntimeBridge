import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../Models/Source.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import 'DesktopAniyomiSourceMethods.dart';
import 'JniBridge.dart';
import '../Runtime/RuntimePaths.dart';
import '../Runtime/RuntimeDownloader.dart';
import '../Runtime/RuntimeController.dart';
import 'package:get/get.dart';
import '../Aniyomi/Models/Source.dart';
import '../Mangayomi/http/m_client.dart';

class DesktopAniyomiExtensions extends Extension {
  final _client = MClient.init();

  @override
  String get id => 'aniyomi-desktop';

  @override
  String get name => 'Aniyomi (Desktop)';

  @override
  bool get supportsNovel => false;

  @override
  SourceMethods createSourceMethods(Source source) =>
      DesktopAniyomiSourceMethods(source);

  @override
  Future<void> initialize() async {
    if (!Get.isRegistered<RuntimeController>()) {
      Get.put(RuntimeController());
    }

    final paths = RuntimePaths();
    final controller = RuntimeController.it;

    if (controller.isReady.value) {
      final bridgeJarPath = await paths.bridgePath;
      await JniBridge().initialize(bridgeJarPath);
    } else {
      Logger.log(
          "AnymeX Bridge initialization deferred: Runtime not ready or download failed.");
    }

    await super.initialize();

    await Future.wait([
      fetchInstalledAnimeExtensions(),
      fetchInstalledMangaExtensions(),
    ]);

    Logger.log("AnymeX Bridge: Desktop Extensions fetched on startup.");
  }

  Future<String> _getExtensionsPath() async {
    final dir = await RuntimePaths().extensionsDir;
    return dir.path;
  }

  Future<String> _getToolsPath() async {
    final dir = await RuntimePaths().toolsDir;
    return dir.path;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    getInstalledRx(ItemType.anime).value = await _loadInstalled(ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    getInstalledRx(ItemType.manga).value = await _loadInstalled(ItemType.manga);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  Future<List<Source>> _loadInstalled(ItemType type) async {
    try {
      final extPath = await _getExtensionsPath();
      final result = await JniBridge().invokeMethod('loadExtensions', {
        'folderPath': extPath,
      });

      final parsed = <ASource>[];

      for (final e in (result as List)) {
        final map = e as Map<String, dynamic>;
        final detectedType =
            map['type'] == 'anime' ? ItemType.anime : ItemType.manga;
        if (detectedType != type) continue;

        final pkgName = map['pkgName'] as String?;
        final className = map['className'] as String;
        final iconUrl = getVal<String>('desktop_ext_icon_$pkgName') ??
            'https://aniyomi.org/img/logo-128px.png';

        final aSource = ASource(
          id: map['id']?.toString() ?? className,
          name: map['name'] as String?,
          lang: map['lang'] as String?,
          pkgName: pkgName ?? className,
          version: map['version'] as String?,
          isNsfw: map['isNsfw'] as bool? ?? false,
          baseUrl: map['baseUrl'] as String?,
          itemType: detectedType,
          iconUrl: iconUrl,
        );
        aSource.managerId = id;

        parsed.add(aSource);
      }

      return parsed;
    } catch (e) {
      Logger.log('Failed to load desktop extensions: $e');
      return [];
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    final res = await _fetchExtensions(ItemType.anime);
    getAvailableRx(ItemType.anime).value = res;
  }

  @override
  Future<void> fetchMangaExtensions() async {
    final res = await _fetchExtensions(ItemType.manga);
    getAvailableRx(ItemType.manga).value = res;
  }

  @override
  Future<void> fetchNovelExtensions() async {}

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(repos.map((r) => _fetchRepo(r, type)));
    final all = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(all.whereType<ASource>().toList(), type);

    getRawAvailableRx(type).value = List.unmodifiable(all);

    return List.unmodifiable(
      all.where((s) => !installedIds.contains(s.id)),
    );
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode != 200) return const [];
      return compute(_parseExtensions, (res.body, repo.url, type));
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, targetType) = args;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];

      final baseIconUrl = repoUrl.replaceAll('/index.min.json', '');
      final sources = <Source>[];

      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';

        final detectedType = name.startsWith('Aniyomi: ')
            ? ItemType.anime
            : name.startsWith('Tachiyomi: ')
                ? ItemType.manga
                : null;

        if (detectedType != targetType) continue;

        sources.add(
          ASource(
            id: map["sources"] != null &&
                    map["sources"] is List &&
                    (map["sources"] as List).isNotEmpty
                ? (map["sources"] as List).first['id']?.toString() ?? ''
                : '',
            name: detectedType == ItemType.anime
                ? name.substring(9)
                : name.substring(10),
            pkgName: map['pkg'],
            apkName: map['apk'],
            lang: map['lang'],
            version: map['version'],
            isNsfw: map['isNsfw'] ?? false,
            itemType: detectedType,
            repo: repoUrl,
            iconUrl: "$baseIconUrl/icon/${map['pkg']}.png",
          ),
        );
      }

      final Map<String, List<ASource>> grouped = {};
      for (final s in sources) {
        final key = (s as ASource).pkgName ?? s.name ?? "unknown";
        grouped.putIfAbsent(key, () => []).add(s);
      }

      final filtered = <ASource>[];
      for (final group in grouped.values) {
        if (group.length > 1) {
          final allSource = group.firstWhere((s) => s.lang == 'all',
              orElse: () => group.firstWhere((s) => s.lang == 'en',
                  orElse: () => group.first));
          for (final s in group) {
            s.langs = group;
          }
          filtered.add(allSource);
        } else {
          filtered.add(group.first);
        }
      }

      return List.unmodifiable(filtered);
    } catch (e) {
      debugPrint("AnymeXExtensionBridge: [Desktop Source] Failed to parse extensions from $repoUrl: $e");
      return const [];
    }
  }

  void _detectUpdates(List<ASource> available, ItemType type) {
    final installed = getInstalledRx(type).value.whereType<ASource>().toList();
    final repoMap = {for (var s in available) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..apkName = repo.apkName
          ..iconUrl = repo.iconUrl
          ..versionLast = repo.version;

        changed = true;
      }
    }

    if (changed) {
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final repos = _loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) return;

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final repo = Repo(url: repoUrl, managerId: id);
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      final parsed = await compute(
        _parseExtensions,
        (res.body, repoUrl, type),
      );

      final rx = getAvailableRx(type);
      final existing = rx.value;
      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);
      getReposRx(type).value = updatedRepos;
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = _loadRepos(type)
          .where((r) => r.url != repoUrl)
          .toList(growable: false);
      _saveRepos(repos, type);

      final rx = getAvailableRx(type);
      rx.value = rx.value.where((s) => s.repo != repoUrl).toList();

      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove repo $repoUrl: $e");
    }
  }

  List<Repo> _loadRepos(ItemType type) {
    final newKey = 'aniyomi${type.name}Repos';
    final oldKey = 'aniyomi${type.name}ReposV2';

    final encoded =
        getVal<List<String>>(newKey) ?? getVal<List<String>>(oldKey);
    if (encoded == null || encoded.isEmpty) return const [];

    return encoded
        .map((e) => Repo.fromJson(jsonDecode(e)))
        .toSet()
        .toList(growable: false);
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    final key = 'aniyomi${type.name}Repos';
    setVal(
      key,
      repos.toSet().map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    var aSource = source as ASource;
    var process;
    if (aSource.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final pkgName = aSource.pkgName ??
          aSource.apkName?.replaceAll('.apk', '') ??
          'unknown_ext';

      final toolsDir = await _getToolsPath();
      final jrePaths = RuntimePaths();
      final javaPath = await jrePaths.javaExecutablePath;

      if (javaPath == null) {
        throw Exception("Java executable not found. Cannot run dex2jar.");
      }

      final dex2jarExt = Platform.isWindows ? 'bat' : 'sh';
      final dex2jarPath =
          p.join(toolsDir, 'dex-tools-v2.4', 'd2j-dex2jar.$dex2jarExt');
      
      if (!File(dex2jarPath).existsSync()) {
        final zipUri = "https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip";
        final zipPath = p.join(toolsDir, 'dex2jar.zip');

        final res = await _client.get(Uri.parse(zipUri));
        if (res.statusCode != 200 && res.statusCode != 302) {
          throw Exception('Failed to download Dex2Jar: HTTP ${res.statusCode}');
        }
        File(zipPath).writeAsBytesSync(res.bodyBytes);

        final setupCommand =
            "Expand-Archive '$zipPath' -DestinationPath '$toolsDir' -Force; Remove-Item '$zipPath'";
        process = await Process.run('powershell', ['-Command', setupCommand]);
        if (process.exitCode != 0) {
          throw Exception('Failed to install Dex2Jar: ${process.stderr}');
        }
      }

      final extDir = await _getExtensionsPath();
      final tempZipPath = p.join(extDir, '$pkgName.zip');
      final tempExtractedPath = p.join(extDir, '${pkgName}_extracted');

      final apkRes = await _client.get(Uri.parse(aSource.apkUrl!));
      if (apkRes.statusCode != 200) {
        throw Exception(
            'Failed to download extension APK: HTTP ${apkRes.statusCode}');
      }
      File(tempZipPath).writeAsBytesSync(apkRes.bodyBytes);

      if (Directory(tempExtractedPath).existsSync()) {
        Directory(tempExtractedPath).deleteSync(recursive: true);
      }
      Directory(tempExtractedPath).createSync(recursive: true);

      final extractCommand =
          "Expand-Archive '$tempZipPath' -DestinationPath '$tempExtractedPath' -Force";
      process = await Process.run('powershell', ['-Command', extractCommand]);

      if (process.exitCode != 0) {
        throw Exception('Failed to extract extension APK');
      }

      final classesDex = p.join(tempExtractedPath, 'classes.dex');
      if (!File(classesDex).existsSync()) {
        throw Exception("No classes.dex found in APK. Not a valid extension.");
      }

      final outJarPath = p.join(extDir, '$pkgName.jar');
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['+x', dex2jarPath]);
      }

      process = await Process.run(
          dex2jarPath, ['--force', classesDex, '-o', outJarPath],
          environment: {'JAVA_HOME': p.dirname(p.dirname(javaPath))});

      if (process.exitCode != 0) {
        throw Exception(
            'Failed to run dex2jar compilation: ${process.stderr}\n${process.stdout}');
      }

      if (aSource.iconUrl != null) {
        setVal('desktop_ext_icon_${pkgName}', aSource.iconUrl);
      }

      try {
        if (File(tempZipPath).existsSync()) File(tempZipPath).deleteSync();
        if (Directory(tempExtractedPath).existsSync()) {
          Directory(tempExtractedPath).deleteSync(recursive: true);
        }
      } catch (e) {
        Logger.log('Cleanup warning: $e');
      }

      final avail = getAvailableRx(aSource.itemType!);
      avail.value = avail.value.where((e) => e.id != aSource.id).toList();

      if (aSource.itemType == ItemType.anime) {
        await fetchInstalledAnimeExtensions();
      } else {
        await fetchInstalledMangaExtensions();
      }
    } catch (e) {
      Logger.log('Error installing desktop source: $e');
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;
    final pkgName = s.pkgName;
    if (pkgName == null || pkgName.isEmpty) {
      throw Exception('Source ID required');
    }

    try {
      try {
        await JniBridge().invokeMethod('unloadExtension', {'sourceId': s.id});
      } catch (e) {
        Logger.log('Warning: Could not natively unload extension from JVM: $e');
      }

      final extPath = await _getExtensionsPath();
      final jarPath = p.join(extPath, '$pkgName.jar');

      if (File(jarPath).existsSync()) File(jarPath).deleteSync();
      KvStore.remove('desktop_ext_icon_${pkgName}');

      final raw = getRawAvailableRx(s.itemType!).value;
      final installed =
          getInstalledRx(s.itemType!).value.where((e) => e.id != s.id).toList();
      getInstalledRx(s.itemType!).value = installed;

      final installedIds = installed.map((e) => e.id).toSet();
      getAvailableRx(s.itemType!).value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );

      Logger.log('Successfully uninstalled desktop package: $pkgName');
    } catch (e) {
      Logger.log('Error uninstalling $pkgName: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  @override
  Future<void> cancelRequest(String token) async {}
}
