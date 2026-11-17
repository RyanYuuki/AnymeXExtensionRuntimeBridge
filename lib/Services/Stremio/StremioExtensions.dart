import 'dart:async';
import 'dart:convert';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import 'Models/StremioManifest.dart';
import 'StremioHttpClient.dart';
import 'StremioSourceMethods.dart';

class StremioExtensions extends Extension {
  static const String _installedAddonUrlsKey = 'stremio_installed_manifest_urls';
  static const String _cachedManifestsKey = 'stremio_cached_manifests';
  static const String _userAddedRepoKey = 'stremio_user_added_repo';
  static const String _defaultsSeededKey = 'stremio_defaults_seeded';

  final Map<String, StremioManifest> _manifests = {};

  static final List<String> defaultCommunityAddons = [
    'https://torrentio.strem.fun/manifest.json',
    'https://v3-cinemeta.strem.io/manifest.json',
    'https://opensubtitles-v3.strem.io/manifest.json',
  ];

  List<Repo> get defaultRepos => [
    Repo(
      url: 'https://torrentio.strem.fun/manifest.json',
      name: 'Torrentio',
      iconUrl: 'https://torrentio.strem.fun/images/logo_v1.png',
      managerId: id,
    ),
    Repo(
      url: 'https://v3-cinemeta.strem.io/manifest.json',
      name: 'Cinemeta',
      iconUrl: 'https://v3-cinemeta.strem.io/logo.png',
      managerId: id,
    ),
    Repo(
      url: 'https://opensubtitles-v3.strem.io/manifest.json',
      name: 'OpenSubtitles',
      iconUrl: 'https://opensubtitles-v3.strem.io/logo.png',
      managerId: id,
    ),
  ];

  @override
  String get id => 'stremio';

  @override
  String get name => 'Stremio';

  @override
  String get icon => 'https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/webp/stremio.webp';

  @override
  bool get supportsAnime => true;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => false;

  List<StremioManifest> get allInstalledManifests => _manifests.values.toList();

  @override
  SourceMethods createSourceMethods(Source source) {
    final manifest = _manifests[source.id] ??
        _manifests[source.baseUrl] ??
        StremioManifest(
          id: source.id ?? '',
          name: source.name ?? '',
          version: source.version ?? '1.0.0',
          transportUrl: source.baseUrl ?? '',
        );

    return StremioSourceMethods(
      source,
      manifest,
      allInstalledManifests: () => allInstalledManifests,
    );
  }

  @override
  Future<void> initialize() async {
    getReposRx(ItemType.anime).value = _loadRepos(ItemType.anime);
    await super.initialize();
    await _loadInstalledFromStorage();
    await fetchAnimeExtensions();
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final repos = encoded.map((e) => Repo.fromJson(jsonDecode(e))).toList();
        final userAdded = getVal<bool>(_userAddedRepoKey) ?? false;
        if (!userAdded) {
          final defaultUrls = defaultCommunityAddons.toSet();
          final onlyDefaults = repos.every((r) => defaultUrls.contains(r.url));
          if (onlyDefaults) {
            _saveRepos([], type);
            return [];
          } else {
            setVal(_userAddedRepoKey, true);
            setVal(_defaultsSeededKey, true);
            return repos;
          }
        }
        return repos;
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

  Future<void> _loadInstalledFromStorage() async {
    try {
      final rawUrls = getVal<String>(_installedAddonUrlsKey);
      List<String> urls = [];
      if (rawUrls != null && rawUrls.isNotEmpty) {
        final decoded = jsonDecode(rawUrls);
        if (decoded is List) {
          urls = decoded.map((e) => e.toString()).toList();
        }
      }

      final rawCached = getVal<String>(_cachedManifestsKey);
      if (rawCached != null && rawCached.isNotEmpty) {
        try {
          final decodedCache = jsonDecode(rawCached);
          if (decodedCache is Map) {
            for (final entry in decodedCache.entries) {
              final manifestMap = Map<String, dynamic>.from(entry.value as Map);
              final manifest = StremioManifest.fromJson(manifestMap, transportUrl: entry.key.toString());
              _manifests[manifest.id] = manifest;
              _manifests[manifest.transportUrl] = manifest;
            }
          }
        } catch (e) {
          Logger.log('Failed to parse cached Stremio manifests: $e');
        }
      }

      final installedSources = <Source>[];
      for (final url in urls) {
        final manifest = _manifests[url] ?? await _fetchAndCacheManifest(url);
        if (manifest != null) {
          installedSources.add(_manifestToSource(manifest, repoUrl: url));
        }
      }

      getInstalledRx(ItemType.anime).value = installedSources;
    } catch (e) {
      Logger.log('Failed to load installed Stremio addons: $e');
    }
  }

  Future<StremioManifest?> _fetchAndCacheManifest(String rawUrl) async {
    try {
      final normalizedUrl = StremioHttpClient.normalizeManifestUrl(rawUrl);
      var json = await StremioHttpClient.getJson(normalizedUrl);
      if (json is! Map<String, dynamic> && rawUrl != normalizedUrl) {
        json = await StremioHttpClient.getJson(rawUrl);
      }
      if (json is Map<String, dynamic>) {
        final manifest = StremioManifest.fromJson(json, transportUrl: normalizedUrl);
        _manifests[manifest.id] = manifest;
        _manifests[manifest.transportUrl] = manifest;
        _manifests[rawUrl] = manifest;
        _persistManifestCache();
        return manifest;
      }
    } catch (e) {
      Logger.log('Failed to fetch Stremio manifest for $rawUrl: $e');
    }
    return null;
  }

  void _persistManifestCache() {
    try {
      final map = <String, dynamic>{};
      for (final entry in _manifests.entries) {
        map[entry.key] = entry.value.toJson();
      }
      setVal(_cachedManifestsKey, jsonEncode(map));
    } catch (e) {
      Logger.log('Failed to persist Stremio manifest cache: $e');
    }
  }

  Source _manifestToSource(StremioManifest manifest, {String? repoUrl}) {
    return Source(
      id: manifest.id,
      name: manifest.name,
      baseUrl: manifest.transportUrl,
      lang: 'all',
      iconUrl: manifest.logo ?? '',
      version: manifest.version,
      itemType: ItemType.anime,
      managerId: id,
      repo: repoUrl ?? manifest.transportUrl,
      supportsPopular: true,
      supportsLatest: true,
    );
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await _loadInstalledFromStorage();
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
      final manifest = _manifests[repo.url] ?? await _fetchAndCacheManifest(repo.url);
      if (manifest != null) {
        final src = _manifestToSource(manifest, repoUrl: repo.url);
        if (!installed.any((s) => s.id == src.id || s.baseUrl == src.baseUrl)) {
          available.add(src);
        }
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
    final url = source.baseUrl ?? '';
    StremioManifest? manifest;
    if (url.isNotEmpty) {
      manifest = await _fetchAndCacheManifest(url);
    }

    final rawUrls = getVal<String>(_installedAddonUrlsKey);
    final urls = <String>[];
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls);
        if (decoded is List) {
          urls.addAll(decoded.map((e) => e.toString()));
        }
      } catch (_) {}
    }

    if (url.isNotEmpty && !urls.contains(url)) {
      urls.add(url);
      setVal(_installedAddonUrlsKey, jsonEncode(urls));
    }

    final installedSource = manifest != null ? _manifestToSource(manifest, repoUrl: url) : source;
    final currentInstalled = getInstalledRx(ItemType.anime).value;
    if (!currentInstalled.any((s) => s.id == source.id || s.baseUrl == source.baseUrl)) {
      getInstalledRx(ItemType.anime).value = [...currentInstalled, installedSource];
    }

    final currentAvailable = getAvailableRx(ItemType.anime).value;
    getAvailableRx(ItemType.anime).value =
        currentAvailable.where((s) => s.id != source.id && s.baseUrl != source.baseUrl).toList();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final url = source.baseUrl ?? '';
    final rawUrls = getVal<String>(_installedAddonUrlsKey);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls);
        if (decoded is List) {
          final urls = decoded.map((e) => e.toString()).toList();
          urls.removeWhere((u) => u == url || u == StremioHttpClient.normalizeManifestUrl(url));
          setVal(_installedAddonUrlsKey, jsonEncode(urls));
        }
      } catch (_) {}
    }

    final currentInstalled = getInstalledRx(ItemType.anime).value;
    getInstalledRx(ItemType.anime).value =
        currentInstalled.where((s) => s.id != source.id && s.baseUrl != source.baseUrl).toList();

    final currentAvailable = getAvailableRx(ItemType.anime).value;
    if (!currentAvailable.any((s) => s.id == source.id || s.baseUrl == source.baseUrl)) {
      getAvailableRx(ItemType.anime).value = [...currentAvailable, source];
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    if (source.baseUrl != null) {
      await _fetchAndCacheManifest(source.baseUrl!);
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    final normUrl = StremioHttpClient.normalizeManifestUrl(repoUrl);
    var manifest = await _fetchAndCacheManifest(normUrl);
    manifest ??= await _fetchAndCacheManifest(repoUrl);
    if (manifest == null) return;

    final repos = _loadRepos(type);
    final existingIdx = repos.indexWhere((r) => r.url == normUrl || r.url == repoUrl);
    final repoItem = Repo(
      url: normUrl,
      name: manifest.name,
      iconUrl: manifest.logo,
      managerId: id,
    );

    final updatedRepos = List<Repo>.from(repos);
    if (existingIdx >= 0) {
      updatedRepos[existingIdx] = repoItem;
    } else {
      updatedRepos.add(repoItem);
    }

    final defaultsSeeded = getVal<bool>(_defaultsSeededKey) ?? false;
    if (!defaultsSeeded) {
      setVal(_defaultsSeededKey, true);
      setVal(_userAddedRepoKey, true);
      for (final defRepo in defaultRepos) {
        if (!updatedRepos.any((r) => r.url == defRepo.url)) {
          updatedRepos.add(defRepo);
        }
      }
    } else {
      setVal(_userAddedRepoKey, true);
    }

    _saveRepos(updatedRepos, type);
    getReposRx(type).value = updatedRepos;

    await fetchAnimeExtensions();
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    final normUrl = StremioHttpClient.normalizeManifestUrl(repoUrl);
    final repos = _loadRepos(type);
    repos.removeWhere((r) => r.url == normUrl || r.url == repoUrl);
    _saveRepos(repos, type);
    getReposRx(type).value = repos;

    final currentAvailable = getAvailableRx(type).value;
    getAvailableRx(type).value =
        currentAvailable.where((s) => s.repo != normUrl && s.baseUrl != normUrl && s.repo != repoUrl).toList();
  }

  @override
  Future<void> cancelRequest(String token) async {}
}
