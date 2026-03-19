import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

List<CloudStreamSource> _hydrateCloudStreamSources(Map<String, dynamic> args) {
  final List<dynamic> result = args['result'];
  final Map<String, String?> metas = args['metas'];

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

    return CloudStreamSource.fromJson(map);
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
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.cs3'));
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
    final allAvailable = <Source>[];

    for (final repo in repos) {
      try {
        final response = await http.get(Uri.parse(repo.url));
        if (response.statusCode == 200) {
          final List<dynamic> data =
              await compute(_decodeJsonList, response.body);
          for (final item in data) {
            allAvailable
                .add(CloudStreamSource.fromJson(item..['repo'] = repo.url));
          }
        }
      } catch (e, st) {
        Logger.log("Failed to fetch CloudStream repo ${repo.url}: $e - $st");
      }
    }

    final installedNames =
        installedAnimeExtensions.value.map((e) => e.name).toSet();
    final installedInternalNames = installedAnimeExtensions.value
        .map((e) => (e as CloudStreamSource).internalName)
        .where((name) => name != null)
        .toSet();

    availableAnimeExtensions.value = allAvailable.where((s) {
      final source = s as CloudStreamSource;
      return !installedNames.contains(source.name) &&
          !installedInternalNames.contains(source.internalName);
    }).toList();
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
        final internalName = map['internalName'] ?? map['name'];
        metas[internalName as String] = getVal<String>('cs_meta_$internalName');
      }

      final sources = await compute(_hydrateCloudStreamSources, {
        'result': result,
        'metas': metas,
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
    if (source is CloudStreamSource && source.pluginUrl != null) {
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
        await file.writeAsBytes(response.bodyBytes);

        Logger.log("Saved CloudStream plugin to ${file.path}");

        final bool success = await platform.invokeMethod(
          'loadPlugin',
          {
            'path': file.path,
          },
        );

        if (success) {
          Logger.log("Successfully loaded CloudStream plugin: ${source.name}");
          
          final metaToSave = {
            'iconUrl': source.iconUrl,
            'language': source.lang,
            'version': source.version,
            'versionLast': source.versionLast,
            'pluginUrl': source.pluginUrl,
            'repo': source.repo,
          };
          final encodedMeta = await compute(_encodeCloudStreamMeta, metaToSave);
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
    await installSource(source);
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
