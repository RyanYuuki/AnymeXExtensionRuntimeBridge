import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../anymex_extension_runtime_bridge.dart';
import 'CloudStreamSourceMethods.dart';

List<dynamic> _decodeJsonList(String body) => jsonDecode(body) as List<dynamic>;
Map<String, dynamic> _decodeJsonMap(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

String _encodeCloudStreamMeta(Map<String, dynamic> data) => jsonEncode(data);

String _normalizeName(String? name) {
  if (name == null) return '';
  return name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
}


List<CloudStreamSource> _hydrateCloudStreamSources(Map<String, dynamic> args) {
  final List<dynamic> result = args['result'];
  final Map<String, String?> metas = args['metas'];
  final String managerId = args['managerId'] as String? ?? 'cloudstream';

  return result.map((e) {
    final map = Map<String, dynamic>.from(e);
    final internalName = map['internalName'] ?? map['name'];
    final metaStr = metas[internalName];

    if (metaStr != null && metaStr.isNotEmpty) {
      try {
        final meta = jsonDecode(metaStr) as Map<String, dynamic>;
        map['iconUrl'] = meta['iconUrl'] ?? map['iconUrl'];
        map['language'] = meta['language'] ?? map['language'];
        map['version'] = meta['version'] ?? map['version'];
        map['versionLast'] = meta['versionLast'] ?? map['versionLast'];
        map['pluginUrl'] = meta['pluginUrl'] ?? map['pluginUrl'];
        map['repo'] = meta['repo'] ?? map['repo'];
      } catch (_) {}
    }

    return CloudStreamSource.fromJson(map)..managerId = managerId;
  }).toList();
}

class CloudStreamExtensions extends Extension {
  @override
  String get id => 'cloudstream';

  @override
  String get name => 'CloudStream';

  @override
  SourceMethods createSourceMethods(Source source) =>
      CloudStreamSourceMethods(source);

  static const platform = MethodChannel('cloudstreamExtensionBridge');

  final Rx<List<Source>> installedAnimeExtensions = Rx([]);
  final Rx<List<Source>> availableAnimeExtensions = Rx([]);

  @override
  bool get supportsNovel => false;
  @override
  bool get supportsManga => false;
  @override
  bool get requiresPlugin => true;

  @override
  Future<void> initialize() async {
    await platform.invokeMethod('initialize');
    await loadPersistedPlugins();
    await super.initialize();
  }

  Future<void> loadPersistedPlugins() async {
    try {
      final dir =
          await AnymeXExtensionBridge.context.getCloudStreamPluginDirectory();
      if (dir == null) return;

      if (await dir.exists()) {
        final allFiles = dir.listSync().whereType<File>();
        for (final file in allFiles) {
          if (file.path.contains('.old_')) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }

        final files = allFiles.where((f) => f.path.endsWith('.cs3'));
        for (final file in files) {
          try {
            await platform.invokeMethod('loadPlugin', {'path': file.path});
            Logger.log("Loaded persisted CloudStream plugin: ${file.path}");
          } catch (e) {
            Logger.log(
                "Failed to load persisted CloudStream plugin ${file.path}: $e");
          }
        }
      }
    } catch (e) {
      Logger.log("Error loading persisted CloudStream plugins: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    final repos = _loadRepos();
    print('CloudStream repos to fetch: ${repos.map((r) => r.url).toList()}');
    final allAvailable = <Source>[];

    for (final repo in repos) {
      try {
        final response = await http.get(Uri.parse(repo.url));
        if (response.statusCode == 200) {
          final List<dynamic> data =
              await compute(_decodeJsonList, response.body);
          for (final item in data) {
            allAvailable.add(
              CloudStreamSource.fromJson(item..['repo'] = repo.url)
                ..managerId = id,
            );
          }
        }
      } catch (e, st) {
        Logger.log("Failed to fetch CloudStream repo ${repo.url}: $e - $st");
      }
    }

    final availableByName = <String, CloudStreamSource>{};
    for (final s in allAvailable) {
      final cs = s as CloudStreamSource;
      final norm = _normalizeName(cs.internalName ?? cs.name);
      final normName = _normalizeName(cs.name);
      availableByName[norm] = cs;
      if (norm != normName) availableByName[normName] = cs;
    }

    bool installedChanged = false;
    final updatedInstalled = installedAnimeExtensions.value.map((s) {
      final cs = s as CloudStreamSource;
      final normInternal = _normalizeName(cs.internalName ?? cs.name);
      final normName = _normalizeName(cs.name);
      final available = availableByName[normInternal] ?? availableByName[normName];
      if (available != null) {
        final installedVersion = _parseVersion(cs.version);
        final repoVersion = _parseVersion(available.version);
        final updateAvailable = repoVersion > installedVersion;
        if (updateAvailable != (cs.hasUpdate ?? false)) {
          installedChanged = true;
          cs.hasUpdate = updateAvailable;
          if (updateAvailable) {
            cs.pluginUrl = available.pluginUrl ?? cs.pluginUrl;
            cs.versionLast = available.version;
          }
        }
      }
      return cs;
    }).toList();

    if (installedChanged) {
      installedAnimeExtensions.value = List<Source>.from(updatedInstalled);
    }

    final installedNames =
        updatedInstalled.map((e) => _normalizeName(e.name)).toSet();
    final installedInternalNames = updatedInstalled
        .map((e) => (e).internalName)
        .where((name) => name != null)
        .map((name) => _normalizeName(name))
        .toSet();

    availableAnimeExtensions.value = allAvailable.where((s) {
      final source = s as CloudStreamSource;
      final normName = _normalizeName(source.name);
      final normInternalName = _normalizeName(source.internalName);
      return !installedNames.contains(normName) &&
          !installedInternalNames.contains(normName) &&
          !installedNames.contains(normInternalName) &&
          !installedInternalNames.contains(normInternalName);
    }).toList();
  }

  int _parseVersion(String? version) {
    if (version == null || version.isEmpty) return 0;
    final cleaned = version.replaceAll(RegExp(r'^[vV]'), '');
    final parts = cleaned.split(RegExp(r'[.\-]'));
    try {
      final major = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
      final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
      return major * 1000000 + minor * 1000 + patch;
    } catch (_) {
      return 0;
    }
  }


  @override
  Future<void> fetchMangaExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    try {
      final List<dynamic>? result =
          await platform.invokeMethod('getRegisteredProviders');
      if (result == null) return;

      final metas = <String, String?>{};
      for (final e in result) {
        final map = Map<String, dynamic>.from(e);
        final internalName = map['internalName'] ?? map['name'] as String?;
        if (internalName != null) {
          final norm = _normalizeName(internalName);
          var metaStr = getVal<String>('cs_meta_$norm');
          if (metaStr == null || metaStr.isEmpty) {
            metaStr = getVal<String>('cs_meta_$internalName');
          }
          metas[internalName] = metaStr;
        }
      }

      final sources = await compute(_hydrateCloudStreamSources, {
        'result': result,
        'metas': metas,
        'managerId': id,
      });

      installedAnimeExtensions.value = sources;
    } catch (e) {
      Logger.log("Error fetching installed CloudStream extensions: $e");
    }
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  @override
  Future<void> installSource(Source source) async {
    if (source is CloudStreamSource) {
      if (source.pluginUrl == null || source.pluginUrl!.isEmpty) {
        final normName = _normalizeName(source.name);
        final normInternalName = _normalizeName(source.internalName);
        final repoMatch = availableAnimeExtensions.value.whereType<CloudStreamSource>().firstWhereOrNull((s) {
          final sNormName = _normalizeName(s.name);
          final sNormInternalName = _normalizeName(s.internalName);
          return sNormName == normName ||
                 sNormInternalName == normInternalName ||
                 (normInternalName.isNotEmpty && sNormName == normInternalName) ||
                 (sNormInternalName.isNotEmpty && sNormInternalName == normName);
        });

        if (repoMatch != null) {
          source.pluginUrl ??= repoMatch.pluginUrl;
          source.repo ??= repoMatch.repo;
          source.version ??= repoMatch.version;
          source.versionLast ??= repoMatch.version;
          source.iconUrl ??= repoMatch.iconUrl;
        }
      }

      if (source.pluginUrl == null || source.pluginUrl!.isEmpty) {
        throw Exception("Plugin URL is required for installation.");
      }

      try {
        Logger.log(
            "Downloading CloudStream plugin: ${source.name} from ${source.pluginUrl}");

        final response = await http.get(Uri.parse(source.pluginUrl!));
        if (response.statusCode != 200) {
          throw Exception(
              "Failed to download plugin: HTTP ${response.statusCode}");
        }

        final dir =
            await AnymeXExtensionBridge.context.getCloudStreamPluginDirectory();
        if (dir == null) {
          throw Exception("Failed to get CloudStream plugin directory");
        }

        final filename = '${source.internalName ?? source.name}.cs3';
        final file = File(p.join(dir.path, filename));

        final tempFile = File(p.join(dir.path, '$filename.tmp'));
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        await tempFile.writeAsBytes(response.bodyBytes);

        if (await file.exists()) {
          try {
            await file.delete();
          } catch (e) {
            Logger.log("Failed to delete existing plugin file, attempting rename workaround: $e");
            try {
              final trashFile = File(p.join(dir.path, '$filename.old_${DateTime.now().millisecondsSinceEpoch}'));
              await file.rename(trashFile.path);
            } catch (renameError) {
              Logger.log("Failed to rename locked plugin file: $renameError");
            }
          }
        }

        try {
          await tempFile.rename(file.path);
        } catch (_) {
          await file.writeAsBytes(response.bodyBytes);
        }

        Logger.log("Saved CloudStream plugin to ${file.path}");

        final bool success = await platform.invokeMethod(
          'loadPlugin',
          {
            'path': file.path,
          },
        );

        if (success) {
          Logger.log("Successfully loaded CloudStream plugin: ${source.name}");
          
          if (source.versionLast != null && source.versionLast!.isNotEmpty) {
            source.version = source.versionLast;
          }
          source.hasUpdate = false;

          final metaToSave = {
            'iconUrl': source.iconUrl,
            'language': source.lang,
            'version': source.version,
            'versionLast': source.versionLast,
            'pluginUrl': source.pluginUrl,
            'repo': source.repo,
          };
          final encodedMeta = await compute(_encodeCloudStreamMeta, metaToSave);
          final norm = _normalizeName(source.internalName ?? source.name);
          setVal('cs_meta_$norm', encodedMeta);
          setVal('cs_meta_${source.internalName ?? source.name}', encodedMeta);

          await fetchInstalledAnimeExtensions();
          await fetchAnimeExtensions();
        } else {
          throw Exception("Bridge failed to load plugin");
        }
      } catch (e) {
        Logger.log("Error installing CloudStream source ${source.name}: $e");
        rethrow;
      }
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    if (source is CloudStreamSource) {
      try {
        Logger.log("Uninstalling CloudStream plugin: ${source.name}");

        final dir =
            await AnymeXExtensionBridge.context.getCloudStreamPluginDirectory();
        if (dir != null) {
          final filename = '${source.internalName ?? source.name}.cs3';
          final file = File(p.join(dir.path, filename));
          if (await file.exists()) {
            await file.delete();
            Logger.log("Deleted plugin file: ${file.path}");
          }
        }

        await platform.invokeMethod(
          'deletePlugin',
          {
            'internalName': source.internalName ?? source.name,
            'repositoryUrl': source.repo ?? '',
          },
        );
        final norm = _normalizeName(source.internalName ?? source.name);
        await KvStore.remove('cs_meta_$norm');
        await KvStore.remove('cs_meta_${source.internalName ?? source.name}');
        Logger.log(
            "Successfully uninstalled CloudStream plugin: ${source.name}");
        await fetchInstalledAnimeExtensions();
        await fetchAnimeExtensions();
      } catch (e) {
        Logger.log("Error uninstalling CloudStream source ${source.name}: $e");
        rethrow;
      }
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    try {
      await uninstallSource(source);
    } catch (_) {}
    await installSource(source);
  }

  @override
  Future<void> cancelRequest(String token) async {
    await AnymeXRuntimeBridge.cancelRequest(token);
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    final repos = _loadRepos();

    if (repos.any((r) => r.url == repoUrl)) {
      Logger.log("CloudStream repo already exists: $repoUrl");
      return;
    }

    late final http.Response response;
    try {
      response = await http.get(Uri.parse(repoUrl));
    } catch (e) {
      Logger.log("CloudStream repo unreachable: $repoUrl — $e");
      throw Exception("Failed to reach repo URL: $repoUrl");
    }

    if (response.statusCode != 200) {
      throw Exception("Repo returned status ${response.statusCode}: $repoUrl");
    }

    late final dynamic decoded;
    try {
      decoded = await compute(_decodeJsonMap, response.body);
    } catch (_) {
      try {
        await compute(_decodeJsonList, response.body);

        repos.add(Repo(url: repoUrl, managerId: 'cloudstream'));
        _saveRepos(repos);
        await fetchAnimeExtensions();
        return;
      } catch (e) {
        throw Exception("Repo URL does not return valid JSON: $repoUrl — $e");
      }
    }

    if (decoded is Map<String, dynamic> &&
        decoded.containsKey('pluginLists') &&
        decoded['pluginLists'] is List) {
      final pluginLists = (decoded['pluginLists'] as List).cast<String>();
      Logger.log(
          "Detected meta-repo at $repoUrl with ${pluginLists.length} sub-repos");

      for (final subUrl in pluginLists) {
        try {
          await addRepo(subUrl, type);
        } catch (e) {
          Logger.log(
              "Failed to add sub-repo $subUrl from meta-repo $repoUrl: $e");
        }
      }
      return;
    }

    repos.add(Repo(url: repoUrl, managerId: 'cloudstream'));
    _saveRepos(repos);
    await fetchAnimeExtensions();
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    final repos = _loadRepos();
    repos.removeWhere((r) => r.url == repoUrl);
    _saveRepos(repos);
    await fetchAnimeExtensions();
  }

  @override
  Rx<List<Source>> getInstalledRx(ItemType type) {
    if (type == ItemType.anime) return installedAnimeExtensions;
    return Rx([]);
  }

  @override
  Rx<List<Source>> getAvailableRx(ItemType type) {
    if (type == ItemType.anime) return availableAnimeExtensions;
    return Rx([]);
  }

  List<Repo> _loadRepos() {
    final key = 'cloudstreamAnimeRepos';
    final encoded = getVal<List<String>>(key);
    if (encoded == null) return [];
    return encoded.map((e) => Repo.fromJson(jsonDecode(e))).toList();
  }

  void _saveRepos(List<Repo> repos) {
    final key = 'cloudstreamAnimeRepos';
    setVal(key, repos.map((e) => jsonEncode(e.toJson())).toList());
  }

  @override
  Rx<List<Repo>> getReposRx(ItemType type) {
    final repos = _loadRepos();
    final rx = Rx<List<Repo>>(repos);
    return rx;
  }

  @override
  Set<String> schemes = {"cloudstreamrepo"};

  @override
  Future<void> handleSchemes(Uri uri) async {
    final urlWithoutScheme =
        uri.toString().replaceFirst('cloudstreamrepo://', '');

    await addRepo(
        urlWithoutScheme.startsWith('http')
            ? urlWithoutScheme
            : 'https://$urlWithoutScheme',
        ItemType.anime);
  }
}
