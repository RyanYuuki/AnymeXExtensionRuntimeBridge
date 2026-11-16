import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import 'Models/PluginManifest.dart';
import 'NuvioPluginRuntime.dart';
import 'NuvioPluginSourceMethods.dart';
import 'NuvioScraperStore.dart';

class NuvioPluginExtensions extends Extension {
  static const String _cachedScrapersKey = 'nuvio_cached_scrapers';
  static const String _installedScraperIdsKey = 'nuvio_installed_scraper_ids';

  final Map<String, PluginScraper> _scrapers = {};
  static final http.Client _httpClient = http.Client();

  @override
  String get id => 'nuvio';

  @override
  String get name => 'Nuvio';

  @override
  String get icon => 'https://avatars.githubusercontent.com/u/267417830';

  @override
  bool get supportsAnime => true;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => false;

  List<PluginScraper> get allInstalledScrapers => _scrapers.values.toList();

  static String normalizeManifestUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return rawUrl;

    final normalizedScheme = (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
        ? trimmed
        : 'https://$trimmed';

    final withoutFragment = normalizedScheme.split('#').first;
    final query = withoutFragment.contains('?') ? withoutFragment.split('?').last : '';
    final path = withoutFragment.split('?').first.replaceAll(RegExp(r'/+$'), '');
    final manifestPath = path.endsWith('/manifest.json') ? path : '$path/manifest.json';
    return query.isEmpty ? manifestPath : '$manifestPath?$query';
  }

  PluginScraper? _lookupScraper(String? id) {
    if (id == null || id.isEmpty) return null;
    if (_scrapers.containsKey(id)) return _scrapers[id];
    final lower = id.toLowerCase();
    for (final s in _scrapers.values) {
      if (s.id.toLowerCase() == lower || s.name.toLowerCase() == lower) {
        return s;
      }
    }
    return null;
  }

  @override
  SourceMethods createSourceMethods(Source source) {
    var scraper = _lookupScraper(source.id);
    if (scraper == null && source.name != null && source.name!.isNotEmpty) {
      scraper = _lookupScraper(source.name);
    }
    if (scraper == null) {
      final sId = source.id ?? '';
      scraper = PluginScraper(
        id: sId,
        name: source.name ?? sId,
        version: source.version ?? '1.0.0',
        filename: 'providers/${sId.toLowerCase()}.js',
        repositoryUrl: source.repo ?? source.baseUrl ?? '',
      );
      _scrapers[sId] = scraper;
    }

    final effectiveRepo = scraper.repositoryUrl.isNotEmpty
        ? scraper.repositoryUrl
        : (source.repo ?? source.baseUrl);

    return NuvioPluginSourceMethods(
      source,
      scraper,
      repositoryUrl: effectiveRepo,
    );
  }

  @override
  Future<void> initialize() async {
    await super.initialize();
    getReposRx(ItemType.anime).value = _loadRepos(ItemType.anime);
    await _loadFromStorage();
    await fetchAnimeExtensions();
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return encoded.map((e) => Repo.fromJson(jsonDecode(e))).toList();
      } catch (_) {}
    }
    return [];
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    setVal(
      '$id${type.name}Repos',
      repos.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _loadFromStorage() async {
    try {
      final rawCached = getVal<String>(_cachedScrapersKey);
      if (rawCached != null && rawCached.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawCached);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final scraper = PluginScraper.fromJson(Map<String, dynamic>.from(item));
                _scrapers[scraper.id] = scraper;
              }
            }
          }
        } catch (e) {
          Logger.log('Failed to parse cached Nuvio scrapers: $e');
        }
      }

      final rawInstalledIds = getVal<String>(_installedScraperIdsKey);
      final installedIds = <String>{};
      if (rawInstalledIds != null && rawInstalledIds.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawInstalledIds);
          if (decoded is List) {
            installedIds.addAll(decoded.map((e) => e.toString()));
          }
        } catch (_) {}
      }

      final installedSources = <Source>[];
      for (final id in installedIds) {
        var scraper = _lookupScraper(id);
        if (scraper == null) {
          scraper = PluginScraper(
            id: id,
            name: id,
            version: '1.0.0',
            filename: '$id.js',
          );
          _scrapers[id] = scraper;
        }
        installedSources.add(_scraperToSource(scraper, repoUrl: scraper.repositoryUrl));
      }

      getInstalledRx(ItemType.anime).value = installedSources;

      final availableSources = <Source>[];
      for (final scraper in _scrapers.values) {
        if (!installedIds.contains(scraper.id)) {
          availableSources.add(_scraperToSource(scraper, repoUrl: scraper.repositoryUrl));
        }
      }

      getAvailableRx(ItemType.anime).value = availableSources;
    } catch (e) {
      Logger.log('Failed to load Nuvio plugins: $e');
    }
  }

  void _persistCache() {
    try {
      final list = _scrapers.values.map((s) => s.toJson()).toList();
      setVal(_cachedScrapersKey, jsonEncode(list));
    } catch (e) {
      Logger.log('Failed to persist Nuvio scraper cache: $e');
    }
  }

  void _persistInstalledIds(Set<String> ids) {
    try {
      setVal(_installedScraperIdsKey, jsonEncode(ids.toList()));
    } catch (e) {
      Logger.log('Failed to persist Nuvio installed IDs: $e');
    }
  }

  Source _scraperToSource(PluginScraper scraper, {String? repoUrl}) {
    return Source(
      id: scraper.id,
      name: scraper.name,
      baseUrl: scraper.repositoryUrl,
      lang: 'all',
      iconUrl: scraper.logo ?? '',
      version: scraper.version,
      itemType: ItemType.anime,
      managerId: id,
      repo: repoUrl ?? scraper.repositoryUrl,
      supportsPopular: true,
      supportsLatest: true,
    );
  }

  Future<List<PluginScraper>> fetchRepositoryScrapers(String repoUrl) async {
    final manifestUrl = normalizeManifestUrl(repoUrl);
    try {
      final res = await _httpClient.get(Uri.parse(manifestUrl));
      if (res.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final manifest = PluginManifest.fromJson(decoded, repositoryUrl: manifestUrl);
        String repoBase = manifestUrl.split('?').first;
        if (repoBase.endsWith('/manifest.json')) {
          repoBase = repoBase.substring(0, repoBase.length - '/manifest.json'.length);
        } else if (repoBase.endsWith('manifest.json')) {
          repoBase = repoBase.substring(0, repoBase.length - 'manifest.json'.length);
        }
        repoBase = repoBase.replaceAll(RegExp(r'/+$'), '');

        final results = <PluginScraper>[];
        for (final s in manifest.scrapers) {
          final cleanFilename = s.filename.replaceAll(RegExp(r'^/+'), '');
          final downloadUrl = (s.filename.startsWith('http://') || s.filename.startsWith('https://'))
              ? s.filename
              : '$repoBase/$cleanFilename';
          s.sourceUrl = downloadUrl;

          String? code = NuvioScraperStore.getScraperCode(s.id);
          code ??= await NuvioScraperStore.loadCode(s.id);
          code ??= await NuvioScraperStore.downloadAndStoreScraper(s.id, downloadUrl);
          if (code != null) {
            s.code = code;
          }
          _scrapers[s.id] = s;
          results.add(s);
        }
        _persistCache();
        return results;
      }
    } catch (e) {
      Logger.log('Failed to fetch Nuvio repository at $repoUrl: $e');
    }
    return [];
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await _loadFromStorage();
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  @override
  Future<void> fetchAnimeExtensions() async {
    final repos = _loadRepos(ItemType.anime);
    final installed = getInstalledRx(ItemType.anime).value;
    final available = <Source>[];

    for (final repo in repos) {
      final scrapers = await fetchRepositoryScrapers(repo.url);
      for (final s in scrapers) {
        final src = _scraperToSource(s, repoUrl: repo.url);
        if (!installed.any((i) => i.id == src.id)) {
          if (!available.any((a) => a.id == src.id)) {
            available.add(src);
          }
        }
      }
    }

    for (final s in _scrapers.values) {
      final src = _scraperToSource(s, repoUrl: s.repositoryUrl);
      if (!installed.any((i) => i.id == src.id) && !available.any((a) => a.id == src.id)) {
        available.add(src);
      }
    }

    getAvailableRx(ItemType.anime).value = available;
  }

  @override
  Future<void> fetchMangaExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> installSource(Source source) async {
    final scraperId = source.id ?? '';
    var scraper = _lookupScraper(scraperId);
    if (scraper == null && source.name != null && source.name!.isNotEmpty) {
      scraper = _lookupScraper(source.name);
    }
    if (scraper == null) {
      scraper = PluginScraper(
        id: scraperId,
        name: source.name ?? scraperId,
        version: source.version ?? '1.0.0',
        filename: '${scraperId.toLowerCase()}.js',
        repositoryUrl: source.repo ?? source.baseUrl ?? '',
      );
      _scrapers[scraperId] = scraper;
    }

    final effectiveRepo = scraper.repositoryUrl.isNotEmpty
        ? scraper.repositoryUrl
        : (source.repo ?? source.baseUrl ?? '');

    if (scraper.code == null || scraper.code!.isEmpty) {
      String? code = NuvioScraperStore.getScraperCode(scraper.id);
      code ??= await NuvioScraperStore.loadCode(scraper.id);
      if (code == null && scraper.sourceUrl != null && scraper.sourceUrl!.isNotEmpty) {
        code = await NuvioScraperStore.downloadAndStoreScraper(scraper.id, scraper.sourceUrl!);
      }
      if (code == null && effectiveRepo.isNotEmpty && scraper.filename.isNotEmpty) {
        final manifestUrl = normalizeManifestUrl(effectiveRepo);
        var repoBase = manifestUrl.split('?').first;
        if (repoBase.endsWith('/manifest.json')) {
          repoBase = repoBase.substring(0, repoBase.length - '/manifest.json'.length);
        } else if (repoBase.endsWith('manifest.json')) {
          repoBase = repoBase.substring(0, repoBase.length - 'manifest.json'.length);
        }
        repoBase = repoBase.replaceAll(RegExp(r'/+$'), '');
        final cleanFilename = scraper.filename.replaceAll(RegExp(r'^/+'), '');
        final codeUrl = (scraper.filename.startsWith('http://') || scraper.filename.startsWith('https://'))
            ? scraper.filename
            : '$repoBase/$cleanFilename';
        code = await NuvioScraperStore.downloadAndStoreScraper(scraper.id, codeUrl);
      }
      if (code != null) {
        scraper.code = code;
      }
    }

    final rawInstalledIds = getVal<String>(_installedScraperIdsKey);
    final installedIds = <String>{};
    if (rawInstalledIds != null && rawInstalledIds.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawInstalledIds);
        if (decoded is List) {
          installedIds.addAll(decoded.map((e) => e.toString()));
        }
      } catch (_) {}
    }

    installedIds.add(scraperId);
    _persistInstalledIds(installedIds);
    _persistCache();

    final installedSource = _scraperToSource(scraper, repoUrl: effectiveRepo);
    final current = getInstalledRx(ItemType.anime).value;
    if (!current.any((s) => s.id == source.id)) {
      getInstalledRx(ItemType.anime).value = [...current, installedSource];
    }

    final available = getAvailableRx(ItemType.anime).value;
    getAvailableRx(ItemType.anime).value = available.where((s) => s.id != source.id).toList();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final scraperId = source.id ?? '';
    await NuvioScraperStore.deleteCode(scraperId);

    final rawInstalledIds = getVal<String>(_installedScraperIdsKey);
    final installedIds = <String>{};
    if (rawInstalledIds != null && rawInstalledIds.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawInstalledIds);
        if (decoded is List) {
          installedIds.addAll(decoded.map((e) => e.toString()));
        }
      } catch (_) {}
    }

    installedIds.remove(scraperId);
    _persistInstalledIds(installedIds);

    final current = getInstalledRx(ItemType.anime).value;
    getInstalledRx(ItemType.anime).value = current.where((s) => s.id != source.id).toList();

    final scraper = _lookupScraper(scraperId);
    if (scraper != null) {
      final available = getAvailableRx(ItemType.anime).value;
      if (!available.any((s) => s.id == scraperId)) {
        getAvailableRx(ItemType.anime).value = [...available, source];
      }
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    final scraperId = source.id ?? '';
    var scraper = _lookupScraper(scraperId);
    if (scraper == null && source.name != null && source.name!.isNotEmpty) {
      scraper = _lookupScraper(source.name);
    }
    if (scraper == null) return;

    final effectiveRepo = scraper.repositoryUrl.isNotEmpty
        ? scraper.repositoryUrl
        : (source.repo ?? source.baseUrl ?? '');

    String? code;
    if (scraper.sourceUrl != null && scraper.sourceUrl!.isNotEmpty) {
      code = await NuvioScraperStore.downloadAndStoreScraper(scraper.id, scraper.sourceUrl!);
    } else if (effectiveRepo.isNotEmpty && scraper.filename.isNotEmpty) {
      final manifestUrl = normalizeManifestUrl(effectiveRepo);
      var repoBase = manifestUrl.split('?').first;
      if (repoBase.endsWith('/manifest.json')) {
        repoBase = repoBase.substring(0, repoBase.length - '/manifest.json'.length);
      } else if (repoBase.endsWith('manifest.json')) {
        repoBase = repoBase.substring(0, repoBase.length - 'manifest.json'.length);
      }
      repoBase = repoBase.replaceAll(RegExp(r'/+$'), '');
      final cleanFilename = scraper.filename.replaceAll(RegExp(r'^/+'), '');
      final codeUrl = (scraper.filename.startsWith('http://') || scraper.filename.startsWith('https://'))
          ? scraper.filename
          : '$repoBase/$cleanFilename';
      code = await NuvioScraperStore.downloadAndStoreScraper(scraper.id, codeUrl);
    }
    if (code != null) {
      scraper.code = code;
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    final scrapers = await fetchRepositoryScrapers(repoUrl);
    final repos = _loadRepos(type);

    if (!repos.any((r) => r.url == repoUrl)) {
      String repoName = 'Nuvio Repository';
      if (scrapers.isNotEmpty && scrapers.first.repositoryUrl.isNotEmpty) {
        repoName = 'Nuvio Scrapers';
      }
      final newRepo = Repo(
        url: repoUrl,
        name: repoName,
        managerId: id,
      );
      final updatedRepos = List<Repo>.from(repos)..add(newRepo);
      _saveRepos(updatedRepos, type);
      getReposRx(type).value = updatedRepos;
    }

    final available = getAvailableRx(ItemType.anime).value;
    final installed = getInstalledRx(ItemType.anime).value;
    final newSources = scrapers
        .map((s) => _scraperToSource(s, repoUrl: repoUrl))
        .where((ns) => !installed.any((i) => i.id == ns.id) && !available.any((s) => s.id == ns.id))
        .toList();

    getAvailableRx(ItemType.anime).value = [...available, ...newSources];
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    final repos = _loadRepos(type);
    repos.removeWhere((r) => r.url == repoUrl);
    _saveRepos(repos, type);
    getReposRx(type).value = repos;

    _scrapers.removeWhere((id, scraper) => scraper.repositoryUrl == repoUrl);
    _persistCache();

    final currentAvailable = getAvailableRx(ItemType.anime).value;
    getAvailableRx(ItemType.anime).value = currentAvailable.where((s) => s.repo != repoUrl).toList();
  }

  @override
  Future<void> cancelRequest(String token) async {}

  void pauseSearch() {
    NuvioPluginRuntime.setSearchPaused(true);
  }

  void resumeSearch() {
    NuvioPluginRuntime.setSearchPaused(false);
  }
}
