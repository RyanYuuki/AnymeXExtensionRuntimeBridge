import 'dart:async';

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
import '../Mangayomi/http/m_client.dart';
import 'JsEngine/PaperbackJsEngine.dart';
import 'Models/PaperbackSource.dart';

class PaperbackSourceMethods extends SourceMethods {
  @override
  final PaperbackSource source;

  late final String sourceId = source.id ?? source.name ?? '';

  PaperbackSourceMethods(Source source)
      : source = source is PaperbackSource
            ? source
            : PaperbackSource.fromJson(source.toJson());

  Completer<void>? _initCompleter;

  Future<void> initialize() {
    if (_initCompleter?.isCompleted ?? false) {
      return _initCompleter!.future;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _doInitialize();
    return _initCompleter!.future;
  }

  Future<void> _doInitialize() async {
    try {
      String code = source.sourceCode ?? '';

      if (code.isEmpty && source.sourceCodeUrl != null && source.sourceCodeUrl!.isNotEmpty) {
        final client = MClient.init();
        final res = await client.get(Uri.parse(source.sourceCodeUrl!));
        if (res.statusCode != 200) {
          throw Exception(
              "Failed to fetch Paperback source code from ${source.sourceCodeUrl}: ${res.statusCode}");
        }
        code = res.body;
        source.sourceCode = code;
      }

      if (code.isEmpty) {
        throw Exception("No source code available for Paperback source ${source.name}");
      }

      await PaperbackJsEngine.instance.loadModule(
        sourceId: sourceId,
        sourceCode: code,
      );

      // Attempt to invoke initialise() if defined on the extension
      try {
        await PaperbackJsEngine.instance.call(
          sourceId: sourceId,
          method: 'initialise',
          params: [],
        );
      } catch (_) {
        // initialise is optional
      }

      _initCompleter?.complete();
    } catch (e, stack) {
      Logger.log("Error initializing PaperbackSourceMethods for $sourceId: $e");
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  Future<dynamic> _call(String method, List<dynamic> params) async {
    await initialize();
    try {
      return await PaperbackJsEngine.instance.call(
        sourceId: sourceId,
        method: method,
        params: params,
      );
    } catch (e) {
      Logger.log("Error in Paperback $sourceId.$method: $e");
      rethrow;
    }
  }

  List<DMedia> _parseMediaList(dynamic raw) {
    final list = <DMedia>[];
    List items = [];

    if (raw is Map) {
      if (raw['items'] is List) {
        items = raw['items'] as List;
      } else if (raw['data'] is List) {
        items = raw['data'] as List;
      }
    } else if (raw is List) {
      items = raw;
    }

    for (final item in items) {
      if (item is Map) {
        final id = item['mangaId'] ?? item['id'] ?? '';
        final title = item['title']?.toString() ?? '';
        final image = item['imageUrl'] ?? item['image'] ?? item['cover'] ?? '';
        if (id.toString().isNotEmpty) {
          list.add(DMedia(
            url: id.toString(),
            title: title,
            cover: image.toString(),
          ));
        }
      }
    }

    return list;
  }

  @override
  Future<Pages> search(
    String query,
    int page,
    List<dynamic> filters, {
    SourceParams? parameters,
  }) async {
    try {
      final offset = (page - 1) * 32;
      final queryParam = {'title': query};
      final metadataParam = {'offset': offset, 'page': page};

      final res = await _call('getSearchResults', [queryParam, metadataParam]);
      final mediaList = _parseMediaList(res);

      bool hasNext = mediaList.length >= 20;
      if (res is Map && res['metadata'] != null) {
        hasNext = true;
      }

      return Pages(list: mediaList, hasNextPage: hasNext);
    } catch (e) {
      Logger.log("Error in Paperback search for $sourceId: $e");
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    try {
      dynamic sections;
      try {
        sections = await _call('getDiscoverSections', []);
      } catch (_) {}

      if (sections is List && sections.isNotEmpty) {
        final popularKeywords = ['popular', 'hot', 'featured', 'recommended', 'top', 'trending'];
        Map? targetSection;

        for (final sec in sections) {
          if (sec is Map) {
            final id = (sec['id'] ?? '').toString().toLowerCase();
            final title = (sec['title'] ?? '').toString().toLowerCase();
            if (popularKeywords.any((k) => id.contains(k) || title.contains(k))) {
              targetSection = sec;
              break;
            }
          }
        }

        targetSection ??= sections.first as Map?;

        if (targetSection != null) {
          final res = await _call('getDiscoverSectionItems', [
            targetSection,
            {'page': page, 'offset': (page - 1) * 32}
          ]);
          final list = _parseMediaList(res);
          if (list.isNotEmpty) {
            return Pages(list: list, hasNextPage: list.length >= 20);
          }
        }
      }

      // Fallback: search with Popularity sorting or empty query
      return await search('', page, [], parameters: parameters);
    } catch (e) {
      Logger.log("Error in Paperback getPopular for $sourceId: $e");
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    try {
      dynamic sections;
      try {
        sections = await _call('getDiscoverSections', []);
      } catch (_) {}

      if (sections is List && sections.isNotEmpty) {
        final latestKeywords = ['recent', 'latest', 'chapterupdates', 'update', 'new'];
        Map? targetSection;

        for (final sec in sections) {
          if (sec is Map) {
            final id = (sec['id'] ?? '').toString().toLowerCase();
            final title = (sec['title'] ?? '').toString().toLowerCase();
            if (latestKeywords.any((k) => id.contains(k) || title.contains(k))) {
              targetSection = sec;
              break;
            }
          }
        }

        if (targetSection != null) {
          final res = await _call('getDiscoverSectionItems', [
            targetSection,
            {'page': page, 'offset': (page - 1) * 32}
          ]);
          final list = _parseMediaList(res);
          if (list.isNotEmpty) {
            return Pages(list: list, hasNextPage: list.length >= 20);
          }
        }
      }

      // Fallback to search
      return await search('', page, [], parameters: parameters);
    } catch (e) {
      Logger.log("Error in Paperback getLatestUpdates for $sourceId: $e");
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final resultMedia = DMedia(
      title: media.title,
      url: media.url,
      cover: media.cover,
    );

    try {
      final mangaId = media.url ?? '';
      final rawDetails = await _call('getMangaDetails', [mangaId]);

      Map? mangaInfo;
      if (rawDetails is Map) {
        if (rawDetails['mangaInfo'] is Map) {
          mangaInfo = rawDetails['mangaInfo'] as Map;
        } else {
          mangaInfo = rawDetails;
        }
      }

      if (mangaInfo != null) {
        resultMedia.title = mangaInfo['primaryTitle']?.toString() ??
            mangaInfo['title']?.toString() ??
            media.title;
        resultMedia.cover = mangaInfo['thumbnailUrl']?.toString() ??
            mangaInfo['image']?.toString() ??
            media.cover;
        resultMedia.description = mangaInfo['synopsis']?.toString() ??
            mangaInfo['description']?.toString();
        resultMedia.author = mangaInfo['author']?.toString();
        resultMedia.artist = mangaInfo['artist']?.toString();

        // Extract genres / tags
        final tagList = <String>[];
        final tagSections = mangaInfo['tagSections'];
        if (tagSections is List) {
          for (final sec in tagSections) {
            if (sec is Map && sec['tags'] is List) {
              for (final t in sec['tags'] as List) {
                if (t is Map && t['title'] != null) {
                  tagList.add(t['title'].toString());
                }
              }
            }
          }
        } else if (mangaInfo['tags'] is List) {
          for (final t in mangaInfo['tags'] as List) {
            if (t is Map && t['title'] != null) {
              tagList.add(t['title'].toString());
            } else if (t is String) {
              tagList.add(t);
            }
          }
        }
        if (tagList.isNotEmpty) {
          resultMedia.genre = tagList;
        }
      }

      // Fetch Chapters
      final rawChapters = await _call('getChapters', [
        {
          'mangaId': mangaId,
          'mangaInfo': mangaInfo ?? {},
        }
      ]);

      final episodes = <DEpisode>[];
      List chaptersList = [];
      if (rawChapters is List) {
        chaptersList = rawChapters;
      } else if (rawChapters is Map && rawChapters['data'] is List) {
        chaptersList = rawChapters['data'] as List;
      }

      for (int i = 0; i < chaptersList.length; i++) {
        final c = chaptersList[i];
        if (c is Map) {
          final chapterId = c['chapterId']?.toString() ?? c['id']?.toString() ?? '';
          final numVal = c['chapterNumber'] ?? c['chapNum'] ?? (chaptersList.length - i);
          final title = c['title']?.toString();
          final epNumber = numVal.toString();

          episodes.add(
            DEpisode(
              url: chapterId,
              episodeNumber: epNumber,
              name: (title != null && title.isNotEmpty) ? title : 'Chapter $epNumber',
              dateUpload: c['publishDate']?.toString() ?? c['time']?.toString() ?? '',
              scanlator: c['group']?.toString() ?? c['scanlator']?.toString(),
              sortMap: {
                'mangaId': mangaId,
              },
            ),
          );
        }
      }

      resultMedia.episodes = episodes.reversed.toList();
      return resultMedia;
    } catch (e) {
      Logger.log("Error in Paperback getDetail for $sourceId: $e");
      resultMedia.episodes = [];
      return resultMedia;
    }
  }

  @override
  Future<List<PageUrl>> getPageList(
    DEpisode episode, {
    SourceParams? parameters,
  }) async {
    try {
      final mangaId = episode.sortMap?['mangaId'] ?? '';
      final chapterParam = {
        'chapterId': episode.url,
        'id': episode.url,
        'sourceManga': {
          'mangaId': mangaId,
        },
      };

      final res = await _call('getChapterDetails', [chapterParam]);

      List rawPages = [];
      if (res is Map) {
        if (res['pages'] is List) {
          rawPages = res['pages'] as List;
        } else if (res['data'] is List) {
          rawPages = res['data'] as List;
        }
      } else if (res is List) {
        rawPages = res;
      }

      final pages = <PageUrl>[];
      final headers = <String, String>{
        if (source.baseUrl != null && source.baseUrl!.isNotEmpty)
          'Referer': source.baseUrl!,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      };

      for (final p in rawPages) {
        if (p is String && p.isNotEmpty) {
          pages.add(PageUrl(p, headers: headers));
        } else if (p is Map) {
          final u = p['url'] ?? p['imageUrl'] ?? p['image'] ?? p['link'];
          if (u != null && u.toString().isNotEmpty) {
            pages.add(PageUrl(u.toString(), headers: headers));
          }
        }
      }

      return pages;
    } catch (e) {
      Logger.log("Error in Paperback getPageList for $sourceId: $e");
      return [];
    }
  }

  @override
  Future<List<Video>> getVideoList(
    DEpisode episode, {
    SourceParams? parameters,
  }) async =>
      [];

  @override
  Future<String?> getNovelContent(
    String chapterTitle,
    String chapterId, {
    SourceParams? parameters,
  }) async =>
      null;

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<List<SourcePreference>> getPreference() async => [];

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async => true;
}
