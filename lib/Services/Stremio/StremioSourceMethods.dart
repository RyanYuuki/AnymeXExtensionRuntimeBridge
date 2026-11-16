import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import '../../AddonManager.dart';
import '../../Engines/TorrentEngine/TorrServerAddon.dart';
import '../../Engines/TorrentEngine/TorrServerController.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourceParams.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import 'Models/StremioManifest.dart';
import 'Models/StremioMeta.dart';
import 'Models/StremioStream.dart';
import 'StremioHttpClient.dart';
import 'StremioSubtitleResolver.dart';

class StremioSourceMethods extends SourceMethods {
  final Source _source;
  final StremioManifest manifest;
  final List<StremioManifest> Function()? allInstalledManifests;

  static const String cinemetaBaseUrl = 'https://v3-cinemeta.strem.io';

  StremioSourceMethods(
    this._source,
    this.manifest, {
    this.allInstalledManifests,
  });

  @override
  Source get source => _source;

  TorrServerController? _resolveTorrServer() {
    try {
      if (Get.isRegistered<AddonManager>()) {
        final addonManager = Get.find<AddonManager>();
        final torrAddon = addonManager.byId('torrserver');
        if (torrAddon is TorrServerAddon) {
          return torrAddon.controller;
        }
      }
    } catch (_) {}
    return null;
  }

  String _resolveMediaType() {
    final typeIndex = source.itemType?.index ?? 0;
    if (typeIndex == ItemType.anime.index) {
      if (manifest.types.contains('anime')) return 'anime';
      if (manifest.types.contains('series')) return 'series';
      if (manifest.types.contains('tv')) return 'tv';
      if (manifest.types.contains('movie')) return 'movie';
    }
    if (manifest.types.contains('series')) return 'series';
    if (manifest.types.contains('movie')) return 'movie';
    if (manifest.types.contains('tv')) return 'tv';
    return manifest.types.isNotEmpty ? manifest.types.first : 'movie';
  }

  StremioManifestCatalog? _findCatalog({bool forSearch = false, String? preferredType}) {
    final targetType = preferredType ?? _resolveMediaType();

    if (forSearch) {
      final matching = manifest.catalogs.where((c) => c.supportsSearch && c.type == targetType);
      if (matching.isNotEmpty) return matching.first;
      final anySearch = manifest.catalogs.where((c) => c.supportsSearch);
      if (anySearch.isNotEmpty) return anySearch.first;
    }

    final feedCatalogs = manifest.catalogs.where((c) => !c.requiresSearch);
    final typed = feedCatalogs.where((c) => c.type == targetType);
    if (typed.isNotEmpty) return typed.first;

    if (feedCatalogs.isNotEmpty) return feedCatalogs.first;
    return manifest.catalogs.isNotEmpty ? manifest.catalogs.first : null;
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    try {
      final catalog = _findCatalog();
      final targetType = _resolveMediaType();
      final baseUrl = catalog != null ? manifest.transportUrl : cinemetaBaseUrl;
      final cType = catalog != null ? catalog.type : targetType;
      final cId = catalog != null ? catalog.id : 'top';

      final skip = (page - 1) * 100;
      final url = StremioHttpClient.buildCatalogUrl(
        baseUrl,
        cType,
        cId,
        skip: skip > 0 ? skip : null,
      );

      final response = await StremioHttpClient.get(url);
      final decoded = jsonDecode(response);

      final rawMetas = decoded is Map
          ? (decoded['metas'] as List? ?? decoded['metasDetailed'] as List? ?? [])
          : [];

      final list = rawMetas
          .whereType<Map>()
          .map((m) => StremioMetaPreview.fromJson(Map<String, dynamic>.from(m)).toDMedia())
          .toList();

      final hasNextPage = list.length >= 100;
      return Pages(list: list, hasNextPage: hasNextPage);
    } catch (e) {
      Logger.log('getPopular failed for ${manifest.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    try {
      final feedCatalogs = manifest.catalogs.where((c) => !c.requiresSearch).toList();
      final catalog = feedCatalogs.length > 1 ? feedCatalogs[1] : _findCatalog();
      final targetType = _resolveMediaType();
      final baseUrl = catalog != null ? manifest.transportUrl : cinemetaBaseUrl;
      final cType = catalog != null ? catalog.type : targetType;
      final cId = catalog != null ? catalog.id : 'year';

      final skip = (page - 1) * 100;
      final url = StremioHttpClient.buildCatalogUrl(
        baseUrl,
        cType,
        cId,
        skip: skip > 0 ? skip : null,
      );

      final response = await StremioHttpClient.get(url);
      final decoded = jsonDecode(response);

      final rawMetas = decoded is Map
          ? (decoded['metas'] as List? ?? decoded['metasDetailed'] as List? ?? [])
          : [];

      final list = rawMetas
          .whereType<Map>()
          .map((m) => StremioMetaPreview.fromJson(Map<String, dynamic>.from(m)).toDMedia())
          .toList();

      final hasNextPage = list.length >= 100;
      return Pages(list: list, hasNextPage: hasNextPage);
    } catch (e) {
      Logger.log('getLatestUpdates failed for ${manifest.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> search(
    String query,
    int page,
    List<dynamic> filters, {
    SourceParams? parameters,
  }) async {
    try {
      final catalog = _findCatalog(forSearch: true);
      final targetType = _resolveMediaType();
      final baseUrl = catalog != null ? manifest.transportUrl : cinemetaBaseUrl;
      final cType = catalog != null ? catalog.type : targetType;
      final cId = catalog != null ? catalog.id : 'top';

      String? selectedGenre;
      for (final f in filters) {
        if (f is Map && f.containsKey('genre')) {
          selectedGenre = f['genre']?.toString();
        }
      }

      final skip = (page - 1) * 100;
      final url = StremioHttpClient.buildCatalogUrl(
        baseUrl,
        cType,
        cId,
        search: query.isNotEmpty ? query : null,
        genre: selectedGenre,
        skip: skip > 0 ? skip : null,
      );

      final response = await StremioHttpClient.get(url);
      final decoded = jsonDecode(response);

      final rawMetas = decoded is Map
          ? (decoded['metas'] as List? ?? decoded['metasDetailed'] as List? ?? [])
          : [];

      final list = rawMetas
          .whereType<Map>()
          .map((m) => StremioMetaPreview.fromJson(Map<String, dynamic>.from(m)).toDMedia())
          .toList();

      final hasNextPage = list.length >= 100;
      return Pages(list: list, hasNextPage: hasNextPage);
    } catch (e) {
      Logger.log('search failed for ${manifest.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final mediaId = media.url ?? '';
    if (mediaId.isEmpty) return media;

    final type = _resolveMediaType();
    try {
      String response;
      if (manifest.supportsResource('meta', type, mediaId)) {
        try {
          final url = StremioHttpClient.buildMetaUrl(manifest.transportUrl, type, mediaId);
          response = await StremioHttpClient.get(url);
        } catch (_) {
          final cinemetaUrl = StremioHttpClient.buildMetaUrl(cinemetaBaseUrl, type, mediaId);
          response = await StremioHttpClient.get(cinemetaUrl);
        }
      } else {
        final cinemetaUrl = StremioHttpClient.buildMetaUrl(cinemetaBaseUrl, type, mediaId);
        response = await StremioHttpClient.get(cinemetaUrl);
      }

      final decoded = jsonDecode(response);
      if (decoded is Map<String, dynamic>) {
        final detail = StremioMetaDetail.fromJson(decoded);
        return detail.toDMedia();
      }
    } catch (e) {
      Logger.log('getDetail failed for ${manifest.name} ($mediaId): $e');
    }
    return media;
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode, {SourceParams? parameters}) async {
    return [];
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode, {SourceParams? parameters}) async {
    final videoId = episode.url ?? '';
    if (videoId.isEmpty) return [];

    final type = _resolveMediaType();
    final torrServer = _resolveTorrServer();

    try {
      final url = StremioHttpClient.buildStreamUrl(manifest.transportUrl, type, videoId);
      final response = await StremioHttpClient.get(url);
      final decoded = jsonDecode(response);

      final rawStreams = decoded is Map ? (decoded['streams'] as List? ?? []) : [];
      final streamItems = rawStreams
          .whereType<Map>()
          .map((m) => StreamItem.fromJson(
                Map<String, dynamic>.from(m),
                addonName: manifest.name,
                addonId: manifest.id,
              ))
          .toList();

      final allAddons = allInstalledManifests != null ? allInstalledManifests!() : [manifest];
      final externalSubs = await StremioSubtitleResolver.resolveSubtitles(
        installedAddons: allAddons,
        type: type,
        videoId: videoId,
      );

      final videoList = <Video>[];
      for (final item in streamItems) {
        final video = item.toVideo(torrServerController: torrServer);
        if (externalSubs.isNotEmpty) {
          final mergedSubs = [...?video.subtitles, ...externalSubs];
          video.subtitles = mergedSubs;
        }
        videoList.add(video);
      }

      return videoList;
    } catch (e) {
      Logger.log('getVideoList failed for ${manifest.name} ($videoId): $e');
      return [];
    }
  }

  @override
  Stream<Video>? getVideoListStream(DEpisode episode, {SourceParams? parameters}) async* {
    final videos = await getVideoList(episode, parameters: parameters);
    for (final v in videos) {
      yield v;
    }
  }

  @override
  Future<List<dynamic>> getFilterList() async {
    final filters = <dynamic>[];
    for (final cat in manifest.catalogs) {
      for (final ex in cat.extra) {
        if (ex.name == 'genre' && ex.options.isNotEmpty) {
          filters.add({
            'type': 'select',
            'name': 'genre',
            'title': 'Genre',
            'options': ex.options,
          });
        }
      }
    }
    return filters;
  }

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId, {SourceParams? parameters}) async {
    return null;
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    return manifest.config.map((cfg) {
      return SourcePreference(
        key: cfg.key,
        type: cfg.type,
        editTextPreference: EditTextPreference(
          title: cfg.title ?? cfg.key,
          summary: cfg.defaultValue ?? '',
          value: cfg.defaultValue ?? '',
        ),
      );
    }).toList();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return true;
  }
}
