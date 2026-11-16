import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
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
import '../../Settings/KvStore.dart';
import '../Debrid/DebridResolverService.dart';
import 'Models/PluginManifest.dart';
import 'NuvioPluginExtensions.dart';
import 'NuvioPluginRuntime.dart';
import 'NuvioScraperStore.dart';

class NuvioPluginSourceMethods extends SourceMethods {
  final Source _source;
  final PluginScraper scraper;
  final String? repositoryUrl;

  static final http.Client _httpClient = http.Client();

  NuvioPluginSourceMethods(
    this._source,
    this.scraper, {
    this.repositoryUrl,
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
    if (scraper.supportedTypes.contains('movie') &&
        !scraper.supportedTypes.contains('tv') &&
        !scraper.supportedTypes.contains('series')) {
      return 'movie';
    }
    return 'series';
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    try {
      final type = _resolveMediaType();
      final skip = (page - 1) * 20;
      final url = skip > 0
          ? 'https://cinemeta-catalogs.strem.io/top/catalog/$type/top/skip=$skip.json'
          : 'https://cinemeta-catalogs.strem.io/top/catalog/$type/top.json';

      final res = await _httpClient.get(Uri.parse(url));
      if (res.statusCode != 200) {
        return Pages(list: [], hasNextPage: false);
      }

      final data = jsonDecode(res.body);
      final rawList = data['metas'] as List? ?? [];
      final list = rawList.whereType<Map>().take(20).map((m) {
        final id = m['id']?.toString() ?? m['imdb_id']?.toString() ?? '';
        final mType = m['type']?.toString() ?? type;
        final title = m['name']?.toString() ?? 'Unknown';
        final poster = m['poster']?.toString();
        final overview = m['description']?.toString();
        return DMedia(
          title: title,
          url: 'cinemeta:$mType:$id',
          cover: poster,
          description: overview,
        );
      }).toList();

      final hasMore = data['hasMore'] == true || list.length >= 20;
      return Pages(list: list, hasNextPage: hasMore);
    } catch (e) {
      Logger.log('Nuvio getPopular failed for ${scraper.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    try {
      final type = _resolveMediaType();
      final skip = (page - 1) * 20;
      final url = skip > 0
          ? 'https://cinemeta-catalogs.strem.io/year/catalog/$type/year/skip=$skip.json'
          : 'https://cinemeta-catalogs.strem.io/year/catalog/$type/year.json';

      final res = await _httpClient.get(Uri.parse(url));
      if (res.statusCode != 200) {
        return Pages(list: [], hasNextPage: false);
      }

      final data = jsonDecode(res.body);
      final rawList = data['metas'] as List? ?? [];
      final list = rawList.whereType<Map>().take(20).map((m) {
        final id = m['id']?.toString() ?? m['imdb_id']?.toString() ?? '';
        final mType = m['type']?.toString() ?? type;
        final title = m['name']?.toString() ?? 'Unknown';
        final poster = m['poster']?.toString();
        final overview = m['description']?.toString();
        return DMedia(
          title: title,
          url: 'cinemeta:$mType:$id',
          cover: poster,
          description: overview,
        );
      }).toList();

      final hasMore = data['hasMore'] == true || list.length >= 20;
      return Pages(list: list, hasNextPage: hasMore);
    } catch (e) {
      Logger.log('Nuvio getLatestUpdates failed for ${scraper.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters, {SourceParams? parameters}) async {
    if (page > 1) {
      return Pages(list: [], hasNextPage: false);
    }

    try {
      final queries = <Future<http.Response>>[];
      final types = <String>[];

      final supportsSeries = scraper.supportedTypes.isEmpty ||
          scraper.supportedTypes.contains('series') ||
          scraper.supportedTypes.contains('tv') ||
          scraper.supportedTypes.contains('anime');
      final supportsMovie = scraper.supportedTypes.isEmpty ||
          scraper.supportedTypes.contains('movie');

      if (supportsSeries) {
        types.add('series');
        queries.add(_httpClient.get(Uri.parse(
          'https://v3-cinemeta.strem.io/catalog/series/top/search=${Uri.encodeComponent(query)}.json',
        )));
      }
      if (supportsMovie) {
        types.add('movie');
        queries.add(_httpClient.get(Uri.parse(
          'https://v3-cinemeta.strem.io/catalog/movie/top/search=${Uri.encodeComponent(query)}.json',
        )));
      }

      final responses = await Future.wait(queries);
      final seenIds = <String>{};
      final list = <DMedia>[];

      for (var i = 0; i < responses.length; i++) {
        final res = responses[i];
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final metas = data['metas'] as List? ?? [];
          for (final m in metas) {
            if (m is! Map) continue;
            final id = m['id']?.toString() ?? m['imdb_id']?.toString() ?? '';
            if (id.isEmpty || seenIds.contains(id)) continue;
            seenIds.add(id);

            final mType = m['type']?.toString() ?? types[i];
            final title = m['name']?.toString() ?? 'Unknown';
            final poster = m['poster']?.toString();
            final overview = m['description']?.toString();

            list.add(DMedia(
              title: title,
              url: 'cinemeta:$mType:$id',
              cover: poster,
              description: overview,
            ));
          }
        }
      }

      return Pages(list: list, hasNextPage: false);
    } catch (e) {
      Logger.log('Nuvio search failed for ${scraper.name}: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final rawUrl = media.url ?? '';
    if (rawUrl.isEmpty) return media;

    String id;
    String type;

    if (rawUrl.startsWith('cinemeta:')) {
      final parts = rawUrl.split(':');
      type = parts.length > 1 ? parts[1] : 'series';
      id = parts.length > 2 ? parts[2] : rawUrl;
    } else if (rawUrl.startsWith('tmdb:')) {
      final parts = rawUrl.split(':');
      id = parts.length > 1 ? parts[1] : rawUrl;
      type = parts.length > 2 ? parts[2] : 'series';
    } else {
      id = rawUrl;
      type = _resolveMediaType();
    }

    if (!id.startsWith('tt')) {
      if (int.tryParse(id) != null) {
        try {
          final armRes = await _httpClient.get(
            Uri.parse('https://arm.haglund.dev/api/v2/ids?source=anilist&id=$id'),
          ).timeout(const Duration(seconds: 4));
          if (armRes.statusCode == 200) {
            final armData = jsonDecode(armRes.body);
            if (armData is Map && armData['imdb'] != null) {
              final foundImdb = armData['imdb'].toString();
              if (foundImdb.startsWith('tt')) {
                id = foundImdb;
              }
            }
          }
        } catch (_) {}
        if (!id.startsWith('tt')) {
          try {
            final tmdbRes = await _httpClient.get(
              Uri.parse('https://arm.haglund.dev/api/v2/themoviedb?id=$id'),
            ).timeout(const Duration(seconds: 4));
            if (tmdbRes.statusCode == 200) {
              final armData = jsonDecode(tmdbRes.body);
              if (armData is List && armData.isNotEmpty && armData[0] is Map) {
                final imdb = armData[0]['imdb']?.toString();
                if (imdb != null && imdb.startsWith('tt')) {
                  id = imdb;
                }
              }
            }
          } catch (_) {}
        }
      }
      final mTitle = media.title;
      if (!id.startsWith('tt') && mTitle != null && mTitle.isNotEmpty) {
        try {
          final sType = (type == 'tv' || type == 'anime' || type == 'series') ? 'series' : 'movie';
          final searchRes = await _httpClient.get(
            Uri.parse('https://v3-cinemeta.strem.io/catalog/$sType/top/search=${Uri.encodeComponent(mTitle)}.json'),
          ).timeout(const Duration(seconds: 4));
          if (searchRes.statusCode == 200) {
            final searchData = jsonDecode(searchRes.body);
            final metas = searchData['metas'] as List? ?? [];
            if (metas.isNotEmpty && metas[0] is Map) {
              final foundId = metas[0]['id']?.toString() ?? metas[0]['imdb_id']?.toString();
              if (foundId != null && foundId.startsWith('tt')) {
                id = foundId;
              }
            }
          }
        } catch (_) {}
      }
    }

    final cinemetaType = (type == 'tv' || type == 'anime') ? 'series' : type;

    try {
      final detailUri = Uri.parse('https://v3-cinemeta.strem.io/meta/$cinemetaType/$id.json');
      final res = await _httpClient.get(detailUri);
      if (res.statusCode != 200) return media;

      final data = jsonDecode(res.body);
      final meta = data['meta'] as Map? ?? {};
      final title = meta['name']?.toString() ?? media.title;
      final overview = meta['description']?.toString() ?? media.description;
      final poster = meta['poster']?.toString() ?? media.cover;

      final genres = <String>[];
      final rawGenres = meta['genres'] as List? ?? meta['genre'] as List? ?? [];
      for (final g in rawGenres) {
        if (g != null && g.toString().isNotEmpty) {
          genres.add(g.toString());
        }
      }

      final tmdbId = meta['moviedb_id']?.toString() ?? meta['id']?.toString() ?? id;
      final imdbId = meta['imdb_id']?.toString() ?? (id.startsWith('tt') ? id : '');
      final episodes = <DEpisode>[];

      if (cinemetaType == 'series') {
        final rawVideos = meta['videos'] as List? ?? [];
        final videos = rawVideos.whereType<Map>().toList();
        videos.sort((a, b) {
          final sA = (a['season'] is int ? a['season'] as int : int.tryParse(a['season']?.toString() ?? '1') ?? 1);
          final sB = (b['season'] is int ? b['season'] as int : int.tryParse(b['season']?.toString() ?? '1') ?? 1);
          final effSA = sA == 0 ? 999999 : sA;
          final effSB = sB == 0 ? 999999 : sB;
          if (effSA != effSB) return effSA.compareTo(effSB);
          final epA = (a['number'] is int ? a['number'] as int : int.tryParse(a['number']?.toString() ?? '1') ?? 1);
          final epB = (b['number'] is int ? b['number'] as int : int.tryParse(b['number']?.toString() ?? '1') ?? 1);
          return epA.compareTo(epB);
        });
        for (final v in videos) {
          final seasonNum = v['season'] is int
              ? v['season'] as int
              : int.tryParse(v['season']?.toString() ?? '1') ?? 1;
          final epNum = v['number'] is int
              ? v['number'] as int
              : int.tryParse(v['number']?.toString() ?? v['episode']?.toString() ?? '1') ?? 1;
          final epName = v['name']?.toString() ?? 'Episode $epNum';
          final epThumb = v['thumbnail']?.toString();
          final epOverview = v['overview']?.toString() ?? v['description']?.toString();

          episodes.add(DEpisode(
            episodeNumber: epNum.toString(),
            name: seasonNum > 0 ? 'S$seasonNum E$epNum: $epName' : 'S0 E$epNum: $epName',
            url: 'nuvio:$tmdbId:$imdbId:tv:$seasonNum:$epNum',
            thumbnail: epThumb,
            description: epOverview,
            sortMap: {
              'season': seasonNum.toString(),
              'tmdbId': tmdbId,
              'imdbId': imdbId,
              'title': title ?? '',
              'mediaType': 'tv',
            },
          ));
        }
      } else {
        episodes.add(DEpisode(
          episodeNumber: '1',
          name: title,
          url: 'nuvio:$tmdbId:$imdbId:movie',
          description: overview,
          thumbnail: poster,
          sortMap: {
            'season': '1',
            'tmdbId': tmdbId,
            'imdbId': imdbId,
            'title': title ?? '',
            'mediaType': 'movie',
          },
        ));
      }

      return DMedia(
        title: title,
        url: rawUrl,
        cover: poster,
        description: overview,
        genre: genres.isNotEmpty ? genres : media.genre,
        episodes: episodes,
      );
    } catch (e) {
      Logger.log('Nuvio getDetail failed for ${scraper.name}: $e');
      return media;
    }
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode, {SourceParams? parameters}) async {
    return [];
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode, {SourceParams? parameters}) async {
    final epUrl = episode.url ?? '';
    final parts = epUrl.split(':');
    String tmdbId = epUrl;
    String imdbId = '';
    String mediaType = _resolveMediaType();
    int? seasonNum = int.tryParse(episode.sortMap?['season'] ?? episode.sortMap?['Season'] ?? '1') ?? 1;
    int? epNum = int.tryParse(episode.episodeNumber) ?? 1;

    if (parts.isNotEmpty && parts[0] == 'nuvio') {
      if (parts.length >= 4) {
        tmdbId = parts[1];
        imdbId = parts[2];
        mediaType = parts[3];
        if (mediaType == 'tv' || mediaType == 'series') {
          mediaType = 'tv';
          if (parts.length > 4) seasonNum = int.tryParse(parts[4]) ?? seasonNum;
          if (parts.length > 5) epNum = int.tryParse(parts[5]) ?? epNum;
        } else if (mediaType == 'movie') {
          seasonNum = null;
          epNum = null;
        }
      }
    } else if (parts.isNotEmpty && parts[0] == 'cinemeta') {
      if (parts.length >= 3) {
        mediaType = (parts[1] == 'series' || parts[1] == 'tv') ? 'tv' : 'movie';
        final cid = parts[2];
        if (cid.startsWith('tt')) {
          imdbId = cid;
          tmdbId = cid;
        } else {
          tmdbId = cid;
        }
        if (parts.length > 3) seasonNum = int.tryParse(parts[3]) ?? seasonNum;
        if (parts.length > 4) epNum = int.tryParse(parts[4]) ?? epNum;
      }
    } else if (parts.isNotEmpty && parts[0] == 'tmdb') {
      if (parts.length >= 3) {
        tmdbId = parts[1];
        mediaType = (parts[2] == 'series' || parts[2] == 'tv') ? 'tv' : 'movie';
        if (parts.length > 3) seasonNum = int.tryParse(parts[3]) ?? seasonNum;
        if (parts.length > 4) epNum = int.tryParse(parts[4]) ?? epNum;
      }
    } else if (parts.length == 2 && !parts[0].startsWith('http')) {
      tmdbId = parts[0];
      mediaType = parts[1];
    }

    if (tmdbId.startsWith('tt')) {
      if (imdbId.isEmpty) imdbId = tmdbId;
      try {
        final cType = (mediaType == 'tv' || mediaType == 'series') ? 'series' : 'movie';
        final metaRes = await _httpClient.get(
          Uri.parse('https://v3-cinemeta.strem.io/meta/$cType/$tmdbId.json'),
        ).timeout(const Duration(seconds: 4));
        if (metaRes.statusCode == 200) {
          final mData = jsonDecode(metaRes.body);
          final meta = mData['meta'] as Map? ?? {};
          final foundTmdb = meta['moviedb_id']?.toString();
          if (foundTmdb != null && foundTmdb.isNotEmpty && foundTmdb != '0') {
            tmdbId = foundTmdb;
          }
        }
      } catch (_) {}
      if (tmdbId.startsWith('tt')) {
        try {
          final findRes = await _httpClient.get(
            Uri.parse('https://api.themoviedb.org/3/find/$tmdbId?api_key=439c478a771f35c05022f9feabcca01c&external_source=imdb_id'),
          ).timeout(const Duration(seconds: 4));
          if (findRes.statusCode == 200) {
            final fData = jsonDecode(findRes.body);
            final tvResults = fData['tv_results'] as List? ?? [];
            final movieResults = fData['movie_results'] as List? ?? [];
            if (tvResults.isNotEmpty && tvResults[0] is Map) {
              tmdbId = tvResults[0]['id'].toString();
              mediaType = 'tv';
            } else if (movieResults.isNotEmpty && movieResults[0] is Map) {
              tmdbId = movieResults[0]['id'].toString();
              mediaType = 'movie';
            }
          }
        } catch (_) {}
      }
    }

    if (tmdbId.isEmpty || (!tmdbId.startsWith('tt') && int.tryParse(tmdbId) == null)) {
      final candidateTitle = (episode.sortMap?['title'] != null && episode.sortMap!['title']!.isNotEmpty)
          ? episode.sortMap!['title']!
          : (episode.sortMap?['mediaTitle'] != null && episode.sortMap!['mediaTitle']!.isNotEmpty)
              ? episode.sortMap!['mediaTitle']!
              : (episode.name != null && episode.name!.isNotEmpty)
                  ? episode.name!
                  : (_source.name ?? '');
      if (candidateTitle.isNotEmpty) {
        try {
          final sType = (mediaType == 'tv' || mediaType == 'series') ? 'series' : 'movie';
          final searchRes = await _httpClient.get(
            Uri.parse('https://v3-cinemeta.strem.io/catalog/$sType/top/search=${Uri.encodeComponent(candidateTitle)}.json'),
          ).timeout(const Duration(seconds: 4));
          if (searchRes.statusCode == 200) {
            final searchData = jsonDecode(searchRes.body);
            final metas = searchData['metas'] as List? ?? [];
            if (metas.isNotEmpty && metas[0] is Map) {
              imdbId = metas[0]['id']?.toString() ?? metas[0]['imdb_id']?.toString() ?? '';
              tmdbId = metas[0]['moviedb_id']?.toString() ?? imdbId;
            }
          }
        } catch (_) {}
        if (tmdbId.startsWith('tt')) {
          try {
            final findRes = await _httpClient.get(
              Uri.parse('https://api.themoviedb.org/3/find/$tmdbId?api_key=439c478a771f35c05022f9feabcca01c&external_source=imdb_id'),
            ).timeout(const Duration(seconds: 4));
            if (findRes.statusCode == 200) {
              final fData = jsonDecode(findRes.body);
              final tvResults = fData['tv_results'] as List? ?? [];
              final movieResults = fData['movie_results'] as List? ?? [];
              if (tvResults.isNotEmpty && tvResults[0] is Map) {
                tmdbId = tvResults[0]['id'].toString();
                mediaType = 'tv';
              } else if (movieResults.isNotEmpty && movieResults[0] is Map) {
                tmdbId = movieResults[0]['id'].toString();
                mediaType = 'movie';
              }
            }
          } catch (_) {}
        }
      }
    }

    if (tmdbId.startsWith('tt') && imdbId.isEmpty) {
      imdbId = tmdbId;
    }

    if (tmdbId.startsWith('tt') && imdbId.isNotEmpty && !imdbId.startsWith('tt')) {
      final tmp = tmdbId;
      tmdbId = imdbId;
      imdbId = tmp;
    }

    final lookupId = scraper.id;
    String? code = scraper.code ?? NuvioScraperStore.getScraperCode(lookupId);
    code ??= await NuvioScraperStore.loadCode(lookupId);

    if (code == null && lookupId != lookupId.toLowerCase()) {
      code = NuvioScraperStore.getScraperCode(lookupId.toLowerCase());
      code ??= await NuvioScraperStore.loadCode(lookupId.toLowerCase());
    }

    if (code == null || code.isEmpty) {
      if (scraper.sourceUrl != null && scraper.sourceUrl!.isNotEmpty) {
        code = await NuvioScraperStore.downloadAndStoreScraper(lookupId, scraper.sourceUrl!);
      }
      if (code == null || code.isEmpty) {
        final effectiveRepoUrl = scraper.repositoryUrl.isNotEmpty
            ? scraper.repositoryUrl
            : (repositoryUrl ?? _source.repo ?? _source.baseUrl ?? '');
        if (effectiveRepoUrl.isNotEmpty && scraper.filename.isNotEmpty) {
          final manifestUrl = NuvioPluginExtensions.normalizeManifestUrl(effectiveRepoUrl);
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
          code = await NuvioScraperStore.downloadAndStoreScraper(lookupId, codeUrl);
        }
      }
    }

    if (code == null || code.isEmpty) {
      Logger.log('No scraper code found for ${scraper.id}');
      return [];
    }
    scraper.code = code;

    final rawSettings = KvStore.get<String>('nuvio_settings_${scraper.id}') ?? '{}';
    Map<String, dynamic> currentSettings = {};
    try {
      currentSettings = Map<String, dynamic>.from(jsonDecode(rawSettings));
    } catch (_) {}

    final results = await NuvioPluginRuntime.executePlugin(
      scraperId: lookupId,
      code: code,
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: seasonNum,
      episode: epNum,
      scraperSettings: currentSettings,
      timeout: const Duration(seconds: 45),
    );

    Logger.log('Nuvio ${scraper.id} stream count: ${results.length}');

    final torrServer = _resolveTorrServer();
    final isDebridActive = DebridResolverService.isEnabled();
    final videoList = <Video>[];

    for (final res in results) {
      final cleanTitle = res.title.split('\n').first.trim();
      final videoTitle = (res.name != null && res.name!.isNotEmpty)
          ? res.name!
          : (cleanTitle.isNotEmpty ? cleanTitle : scraper.name);
      final quality = res.quality ?? 'Auto';
      final trackSubs = res.subtitles?.map((s) => Track(file: s.url, label: s.name ?? s.language)).toList() ?? [];

      if (res.infoHash != null && res.infoHash!.isNotEmpty) {
        final hash = res.infoHash!.toLowerCase();

        if (isDebridActive) {
          try {
            final debridLink = await DebridResolverService.resolveTorrent(
              infoHash: hash,
              season: seasonNum,
              episode: epNum,
              name: videoTitle,
            );
            if (debridLink != null) {
              videoList.add(Video(
                '[${debridLink.provider}] $videoTitle',
                debridLink.url,
                quality,
                subtitles: trackSubs,
                headers: res.headers,
                extraData: {
                  'infoHash': hash,
                  'provider': debridLink.provider,
                  'isDebrid': true,
                },
              ));
            }
          } catch (e) {
            Logger.log('Debrid resolution failed in Nuvio: $e');
          }
        }

        String streamUrl;
        if (torrServer != null && torrServer.isRunning) {
          streamUrl = torrServer.streamUrl(hash).toString();
        } else {
          streamUrl = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(videoTitle)}';
        }

        videoList.add(Video(
          '[P2P] $videoTitle',
          streamUrl,
          quality,
          subtitles: trackSubs,
          headers: res.headers,
          extraData: {
            'infoHash': hash,
            'seeders': res.seeders,
            'peers': res.peers,
            'size': res.size,
          },
        ));
      } else if (res.url.isNotEmpty) {
        videoList.add(Video(
          videoTitle,
          res.url,
          quality,
          subtitles: trackSubs,
          headers: res.headers,
          extraData: {
            'provider': res.provider,
            'size': res.size,
          },
        ));
      }
    }

    return videoList;
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
    return [];
  }

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId, {SourceParams? parameters}) async {
    return null;
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    final preferences = <SourcePreference>[];

    for (final field in scraper.settings) {
      if (field.type == 'select') {
        preferences.add(SourcePreference(
          key: field.key,
          listPreference: ListPreference(
            title: field.label,
            summary: field.description ?? '',
            entries: field.options.map((o) => o['label'] ?? '').toList(),
            entryValues: field.options.map((o) => o['value'] ?? '').toList(),
            value: field.defaultValue?.toString() ?? '',
          ),
        ));
      } else if (field.type == 'checkbox') {
        preferences.add(SourcePreference(
          key: field.key,
          checkBoxPreference: CheckBoxPreference(
            title: field.label,
            summary: field.description ?? '',
            value: field.defaultValue == true || field.defaultValue == 'true',
          ),
        ));
      } else {
        preferences.add(SourcePreference(
          key: field.key,
          editTextPreference: EditTextPreference(
            title: field.label,
            summary: field.description ?? '',
            value: field.defaultValue?.toString() ?? '',
          ),
        ));
      }
    }

    return preferences;
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    try {
      final rawSettings = KvStore.get<String>('nuvio_settings_${scraper.id}') ?? '{}';
      final currentSettings = Map<String, dynamic>.from(jsonDecode(rawSettings));
      if (pref.key != null) {
        currentSettings[pref.key!] = value;
        KvStore.setSync('nuvio_settings_${scraper.id}', jsonEncode(currentSettings));
        return true;
      }
    } catch (_) {}
    return false;
  }
}
