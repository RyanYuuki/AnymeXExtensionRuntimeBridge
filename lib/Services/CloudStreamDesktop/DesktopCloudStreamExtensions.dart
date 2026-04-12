import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:get/get.dart';
import 'package:archive/archive_io.dart';

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../Models/Source.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Runtime/RuntimeTools.dart';
import '../../Runtime/RuntimePaths.dart';
import '../../Runtime/RuntimeController.dart';
import '../../Runtime/Bridge/BridgeDispatcher.dart';
import '../../Runtime/DesktopExtensionBase.dart';
import 'DesktopCloudStreamSourceMethods.dart';
import '../../anymex_extension_runtime_bridge.dart';

List<dynamic> _decodeJsonList(String body) => jsonDecode(body) as List<dynamic>;
Map<String, dynamic> _decodeJsonMap(String body) =>
    jsonDecode(body) as Map<String, dynamic>;
String _encodeCloudStreamMeta(Map<String, dynamic> data) => jsonEncode(data);

class DesktopCloudStreamExtensions extends DesktopExtensionBase {
  @override
  String get id => 'cloudstream-desktop';

  @override
  String get name => 'CloudStream (Desktop)';

  @override
  bool get supportsNovel => false;

  @override
  bool get supportsManga => false;

  final Rx<List<Source>> installedAnimeExtensions = Rx([]);
  final Rx<List<Source>> availableAnimeExtensions = Rx([]);

  @override
  SourceMethods createSourceMethods(Source source) =>
      DesktopCloudStreamSourceMethods(source);

  Future<String> _getToolsPath() async {
    return getToolsPath();
  }

  Future<String> _getExtensionsPath() async {
    return getExtensionsPath('CloudStream');
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    final installed = await _loadInstalled(ItemType.anime);
    installedAnimeExtensions.value = installed;
    installedAnimeExtensions.refresh();
    Logger.log(
        "AnymeX Bridge: ${installed.length} CloudStream extensions loaded/updated.");
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  Future<List<Source>> _loadInstalled(ItemType type) async {
    try {
      final extPath = await _getExtensionsPath();
      final result = await BridgeDispatcher().invokeMethod('csLoadExtensions', {
        'folderPath': extPath,
      });

      final parsed = <Source>[];
      final metas = <String, Map<String, dynamic>>{};

      for (final e in (result as List)) {
        final map = e as Map<String, dynamic>;

        final internalName = map['name'] as String?;
        if (internalName != null) {
          final metaStr = getVal<String>('desktop_cs_meta_$internalName');
          if (metaStr != null && metaStr.isNotEmpty) {
            try {
              metas[internalName] = jsonDecode(metaStr);
            } catch (_) {}
          }
        }

        final meta = internalName != null ? metas[internalName] : null;

        final source = CloudStreamSource(
          id: map['id']?.toString() ?? '',
          name: map['name'] as String?,
          lang: meta?['language'] as String? ?? map['lang'] as String?,
          version: meta?['version'] as String? ?? map['version'] as String?,
          isNsfw: map['isNsfw'] as bool? ?? false,
          baseUrl: map['baseUrl'] as String?,
          itemType: ItemType.anime,
          iconUrl: meta?['iconUrl'] as String? ??
              'https://raw.githubusercontent.com/recloudstream/cloudstream/master/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
          internalName: internalName,
          repo: meta?['repo'] as String?,
          pluginUrl: meta?['pluginUrl'] as String?,
          jarUrl: meta?['jarUrl'] as String?,
        );
        source.managerId = id;

        parsed.add(source);
      }

      return parsed;
    } catch (e) {
      Logger.log('Failed to load desktop CloudStream plugins: $e');
      return [];
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

        repos.add(Repo(url: repoUrl, managerId: id));
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

    repos.add(Repo(url: repoUrl, managerId: id));
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
  Future<void> installSource(Source source, {String? customPath}) async {
    if (source is CloudStreamSource) {
      final pluginUrl = source.pluginUrl;
      final jarUrl = source.jarUrl;

      if (pluginUrl == null && jarUrl == null) {
        throw Exception(
            "A pluginUrl (.cs3) or jarUrl is required for Desktop extension loading.");
      }

      try {
        Logger.log(
            "Downloading CloudStream plugin for Desktop: ${source.name}");
        final extDir = await _getExtensionsPath();

        final tempDir = Directory(
            p.join(extDir, 'temp_${source.internalName ?? source.name}'));
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        await tempDir.create();

        Logger.log("Fetching CS3 file $pluginUrl for processing...");
        final cs3Res = await http.get(Uri.parse(pluginUrl!));
        if (cs3Res.statusCode != 200) {
          throw Exception("Failed to fetch .cs3 zip from $pluginUrl");
        }

        final cs3Path = p.join(tempDir.path, 'plugin.cs3');
        await File(cs3Path).writeAsBytes(cs3Res.bodyBytes);

        final cs3Bytes = await File(cs3Path).readAsBytes();
        final cs3Archive = ZipDecoder().decodeBytes(cs3Bytes);
        ArchiveFile? dexFile;
        ArchiveFile? metadataFile;
        bool isBridgeManifest = false;

        for (final file in cs3Archive) {
          if (file.name == 'classes.dex') dexFile = file;
          if (file.name == 'plugins.manifest') {
            metadataFile = file;
            isBridgeManifest = false;
          }
          if (file.name == 'manifest.json' && metadataFile == null) {
            metadataFile = file;
            isBridgeManifest = true;
          }
        }

        final finalJarPath =
            p.join(extDir, '${source.internalName ?? source.name}.jar');

        if (jarUrl != null) {
          Logger.log("Fetching JVM JAR file (Legacy)...");
          final jarRes = await http.get(Uri.parse(jarUrl));
          if (jarRes.statusCode != 200) {
            throw Exception("Failed to fetch .jar from $jarUrl");
          }

          final rawJarPath = p.join(tempDir.path, 'raw.jar');
          await File(rawJarPath).writeAsBytes(jarRes.bodyBytes);

          final jarBytes = await File(rawJarPath).readAsBytes();
          final decodedArchive = ZipDecoder().decodeBytes(jarBytes);

          final jarArchive = Archive();
          for (final file in decodedArchive.files) {
            if (file.name != 'manifest.json') {
              jarArchive.addFile(file);
            }
          }

          if (metadataFile != null) {
            if (isBridgeManifest) {
              jarArchive.addFile(ArchiveFile(
                  'manifest.json', metadataFile.size, metadataFile.content));
            } else {
              final csJson =
                  jsonDecode(utf8.decode(metadataFile.content as List<int>));
              final bridgeJson = {
                "pluginClassName": csJson['pluginClassName'] ?? "",
                "name": source.name,
                "version": source.version ?? "1.0.0",
                "authors":
                    (csJson['authors'] as List?)?.join(", ") ?? "Unknown",
                "requires": 1
              };
              final encoded = utf8.encode(jsonEncode(bridgeJson));
              jarArchive.addFile(
                  ArchiveFile('manifest.json', encoded.length, encoded));
            }
          }

          final patchedJarBytes = ZipEncoder().encode(jarArchive);
          await File(finalJarPath).writeAsBytes(patchedJarBytes!);
        } else {
          if (dexFile == null || metadataFile == null) {
            throw Exception(
                "CS3 file missing required classes.dex or metadata (manifest.json/plugins.manifest)");
          }

          Logger.log("Converting .cs3 to JAR via dex2jar...");
          final dexPath = p.join(tempDir.path, 'classes.dex');
          await File(dexPath).writeAsBytes(dexFile.content as List<int>);

          await RuntimeTools().runDex2Jar(dexPath, finalJarPath);

          final jarBytes = await File(finalJarPath).readAsBytes();
          final jarArchive = ZipDecoder().decodeBytes(jarBytes);
          final finalArchive = Archive();
          for (final f in jarArchive.files) {
            if (f.name != 'manifest.json') finalArchive.addFile(f);
          }

          final Map<String, dynamic> bridgeJson;
          if (isBridgeManifest) {
            bridgeJson =
                jsonDecode(utf8.decode(metadataFile.content as List<int>));
          } else {
            final csJson =
                jsonDecode(utf8.decode(metadataFile.content as List<int>));
            bridgeJson = {
              "pluginClassName": csJson['pluginClassName'] ?? "",
              "name": source.name,
              "version": source.version ?? "1.0.0",
              "authors": (csJson['authors'] as List?)?.join(", ") ?? "Unknown",
              "requires": 1
            };
          }
          final encoded = utf8.encode(jsonEncode(bridgeJson));
          finalArchive
              .addFile(ArchiveFile('manifest.json', encoded.length, encoded));

          final finalJarBytes = ZipEncoder().encode(finalArchive);
          await File(finalJarPath).writeAsBytes(finalJarBytes!);
        }

        await tempDir.delete(recursive: true);

        Logger.log(
            "Successfully installed CloudStream plugin: ${source.name} to $finalJarPath");

        final metaToSave = {
          'iconUrl': source.iconUrl,
          'language': source.lang,
          'version': source.version,
          'versionLast': source.versionLast,
          'pluginUrl': source.pluginUrl,
          'repo': source.repo,
          'jarUrl': jarUrl,
        };
        final encodedMeta = await compute(_encodeCloudStreamMeta, metaToSave);
        setVal('desktop_cs_meta_${source.internalName ?? source.name}',
            encodedMeta);

        await fetchInstalledAnimeExtensions();
        await fetchAnimeExtensions();
      } catch (e, s) {
        Logger.log(
            "Error installing desktop CloudStream source ${source.name}: $e - $s");
        rethrow;
      }
    } else {
      throw Exception('Source is not a CloudStreamSource');
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    if (source is CloudStreamSource) {
      try {
        Logger.log("Uninstalling Desktop CloudStream plugin: ${source.name}");

        try {
          await BridgeDispatcher().invokeMethod(
              'unloadExtension', {'sourceId': 'cs_${source.internalName}'});
        } catch (_) {}

        final dir = await _getExtensionsPath();
        final filename = '${source.internalName ?? source.name}.jar';
        final file = File(p.join(dir, filename));

        if (await file.exists()) {
          await file.delete();
          Logger.log("Deleted plugin jar: ${file.path}");
        }

        await KvStore.remove(
            'desktop_cs_meta_${source.internalName ?? source.name}');

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
  Future<void> cancelRequest(String token) async {
    await AnymeXRuntimeBridge.cancelRequest(token);
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
    final key = 'desktopCloudstreamAnimeRepos';
    final encoded = getVal<List<String>>(key);
    if (encoded == null) return [];
    return encoded.map((e) => Repo.fromJson(jsonDecode(e))).toList();
  }

  void _saveRepos(List<Repo> repos) {
    final key = 'desktopCloudstreamAnimeRepos';
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

  Future<void> _extractZip(String archivePath, String targetDir) async {
    await extractZip(archivePath, targetDir);
  }
}
