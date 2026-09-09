import 'dart:convert';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import '../Mangayomi/http/m_client.dart';
import 'Models/PaperbackSource.dart';
import 'PaperbackSourceMethods.dart';

class PaperbackExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'paperback';

  @override
  String get name => 'Paperback';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => true;

  @override
  bool get supportsNovel => false;

  @override
  bool get requiresPlugin => false;

  @override
  SourceMethods createSourceMethods(Source source) =>
      PaperbackSourceMethods(source);

  static (String baseUrl, String manifestUrl) normalizeRepoUrl(String input) {
    String clean = input.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }

    if (clean.toLowerCase().endsWith('/versioning.json')) {
      final base = clean.substring(0, clean.length - '/versioning.json'.length);
      return (base, clean);
    } else {
      return (clean, '$clean/versioning.json');
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {}

  @override
  Future<void> fetchInstalledAnimeExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  @override
  Future<void> fetchMangaExtensions() async {
    final res = await _fetchExtensions();
    getAvailableRx(ItemType.manga).value = res;
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    final installed = _loadInstalled();
    getInstalledRx(ItemType.manga).value = installed;
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final (baseUrl, manifestUrl) = normalizeRepoUrl(repoUrl);
      final uri = Uri.tryParse(manifestUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL: $repoUrl");
      }

      final repos = _loadRepos();

      if (repos.any((r) => r.url == repoUrl || r.url == baseUrl || r.url == manifestUrl)) {
        return;
      }

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch Paperback manifest: ${res.statusCode}");
      }

      final decoded = jsonDecode(res.body);
      String? repoName;
      String? repoIcon;

      if (decoded is Map<String, dynamic>) {
        if (decoded['repository'] is Map) {
          final rep = decoded['repository'] as Map;
          repoName = rep['name']?.toString();
          repoIcon = rep['icon']?.toString();
        }

        final sources = decoded['sources'];
        if (repoName == null && sources is List && sources.isNotEmpty) {
          final first = sources.first;
          if (first is Map && first['developers'] is List && (first['developers'] as List).isNotEmpty) {
            final dev = (first['developers'] as List).first;
            if (dev is Map && dev['name'] != null) {
              repoName = "${dev['name']} Paperback Repo";
            }
          }
        }
      }

      repoName ??= Uri.parse(baseUrl).host;

      final repo = Repo(
        url: repoUrl,
        name: repoName,
        iconUrl: repoIcon,
        managerId: id,
      );

      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos);
      getReposRx(ItemType.manga).value = List.unmodifiable(updatedRepos);

      await fetchMangaExtensions();
    } catch (e) {
      Logger.log("Failed to add Paperback repo: $e");
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    final (baseUrl, manifestUrl) = normalizeRepoUrl(repoUrl);
    final repos = _loadRepos();
    final updated = repos.where((r) =>
        r.url != repoUrl && r.url != baseUrl && r.url != manifestUrl).toList();

    _saveRepos(updated);
    getReposRx(ItemType.manga).value = List.unmodifiable(updated);

    await fetchMangaExtensions();
  }

  Future<List<Source>> _fetchExtensions() async {
    final repos = _loadRepos();
    if (repos.isEmpty) {
      getRawAvailableRx(ItemType.manga).value = const [];
      return const [];
    }

    final futures = repos.map((r) => _fetchRepoSources(r.url));
    final results = await Future.wait(futures);

    final allSources = results.expand((s) => s).toList();

    getRawAvailableRx(ItemType.manga).value = allSources;

    final installed = _loadInstalled();
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(allSources);

    final available = allSources.where((e) => !installedIds.contains(e.id)).toList();
    return available;
  }

  Future<List<PaperbackSource>> _fetchRepoSources(String repoUrl) async {
    try {
      final (baseUrl, manifestUrl) = normalizeRepoUrl(repoUrl);
      final res = await _client.get(Uri.parse(manifestUrl));
      if (res.statusCode != 200) {
        return const [];
      }

      return _parseExtensions(res.body, baseUrl, repoUrl);
    } catch (e) {
      Logger.log("Failed to fetch Paperback sources for $repoUrl: $e");
      return const [];
    }
  }

  List<PaperbackSource> _parseExtensions(
    String body,
    String baseUrl,
    String originalRepoUrl,
  ) {
    try {
      final decoded = jsonDecode(body);
      final sources = <PaperbackSource>[];

      if (decoded is Map<String, dynamic> && decoded['sources'] is List) {
        final list = decoded['sources'] as List;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final sourceId = item['id']?.toString() ?? item['name']?.toString() ?? '';
            if (sourceId.isEmpty) continue;

            final name = item['name']?.toString() ?? sourceId;
            final version = item['version']?.toString() ?? '1.0.0';
            final desc = item['description']?.toString();
            final lang = item['language']?.toString() ?? 'en';
            final rating = item['contentRating']?.toString() ?? 'SAFE';
            final isNsfw = rating == 'ADULT' || rating == 'MATURE';

            String iconUrl = '';
            final iconField = item['icon']?.toString() ?? 'icon.png';
            if (iconField.startsWith('http://') || iconField.startsWith('https://')) {
              iconUrl = iconField;
            } else {
              iconUrl = '$baseUrl/$sourceId/$iconField';
            }

            final scriptUrl = '$baseUrl/$sourceId/index.js';

            List<int>? caps;
            if (item['capabilities'] is List) {
              caps = (item['capabilities'] as List)
                  .map((e) => int.tryParse(e.toString()) ?? 0)
                  .toList();
            }

            String? devAuthor;
            if (item['developers'] is List && (item['developers'] as List).isNotEmpty) {
              final firstDev = (item['developers'] as List).first;
              if (firstDev is Map) {
                devAuthor = firstDev['name']?.toString();
              } else if (firstDev is String) {
                devAuthor = firstDev;
              }
            }

            sources.add(
              PaperbackSource(
                id: sourceId,
                name: name,
                version: version,
                description: desc,
                lang: lang,
                isNsfw: isNsfw,
                iconUrl: iconUrl,
                baseUrl: item['website']?.toString() ?? '',
                sourceCodeUrl: scriptUrl,
                repo: originalRepoUrl,
                managerId: id,
                contentRating: rating,
                capabilities: caps,
                author: devAuthor,
                supportsLatest: true,
                supportsPopular: true,
              ),
            );
          }
        }
      }

      return sources;
    } catch (e) {
      Logger.log("Error parsing Paperback extensions: $e");
      return const [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source is PaperbackSource
        ? source
        : PaperbackSource.fromJson(source.toJson());

    try {
      PaperbackSource? remote;
      final list = getRawAvailableRx(ItemType.manga).value;
      for (final e in list) {
        if (e.id == s.id) {
          remote = e is PaperbackSource ? e : PaperbackSource.fromJson(e.toJson());
          break;
        }
      }

      final target = remote ?? s;

      if (target.sourceCodeUrl == null || target.sourceCodeUrl!.isEmpty) {
        throw Exception("Missing sourceCodeUrl for ${target.name}");
      }

      final res = await _client.get(Uri.parse(target.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Failed to download Paperback extension JS from ${target.sourceCodeUrl}: ${res.statusCode}");
      }

      final installed = PaperbackSource.fromJson(target.toJson())
        ..sourceCode = res.body
        ..hasUpdate = false
        ..versionLast = null;

      final installedList = _loadInstalled();
      installedList.removeWhere((e) => e.id == s.id);
      installedList.add(installed);

      _saveInstalled(installedList);
      getInstalledRx(ItemType.manga).value = List.unmodifiable(installedList);

      final avail = getAvailableRx(ItemType.manga);
      avail.value = avail.value.where((e) => e.id != s.id).toList();
    } catch (e) {
      Logger.log("Paperback install failed for ${s.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    try {
      final installed = _loadInstalled();
      installed.removeWhere((e) => e.id == source.id);

      _saveInstalled(installed);
      getInstalledRx(ItemType.manga).value = List.unmodifiable(installed);

      final raw = getRawAvailableRx(ItemType.manga).value;
      final installedIds = installed.map((e) => e.id).toSet();

      getAvailableRx(ItemType.manga).value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );
    } catch (e) {
      Logger.log("Paperback uninstall failed for ${source.id}: $e");
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  void _detectUpdates(List<Source> available) {
    final installed = _loadInstalled();
    if (installed.isEmpty || available.isEmpty) return;

    final repoMap = {for (final s in available) s.id: s};
    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];
      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version;
        changed = true;
      }
    }

    if (changed) {
      _saveInstalled(installed);
      getInstalledRx(ItemType.manga).value = List.unmodifiable(installed);
    }
  }

  List<Repo> _loadRepos() {
    final encoded = getVal<List<String>>('$id-manga-repos');
    if (encoded == null || encoded.isEmpty) return const [];

    return encoded
        .map((e) => Repo.fromJson(jsonDecode(e)))
        .toList(growable: false);
  }

  void _saveRepos(List<Repo> repos) {
    final key = '$id-manga-repos';
    setVal(
      key,
      repos.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  List<PaperbackSource> _loadInstalled() {
    final encoded = getVal<List<String>>('$id-Installed-manga');
    if (encoded == null || encoded.isEmpty) return [];

    final list = <PaperbackSource>[];
    for (final e in encoded) {
      try {
        list.add(PaperbackSource.fromJson(jsonDecode(e))..managerId = id);
      } catch (_) {}
    }

    return list;
  }

  void _saveInstalled(List<PaperbackSource> list) {
    final key = '$id-Installed-manga';
    setVal(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  @override
  Set<String> get schemes => {"paperback"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.manga);
    }
  }
}
