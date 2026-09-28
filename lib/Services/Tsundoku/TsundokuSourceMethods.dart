import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourceParams.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../../Runtime/Bridge/BridgeDispatcher.dart';
import '../Aniyomi/AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class TsundokuSourceMethods extends SourceMethods {
  @override
  final TSource source;

  static const platform = MethodChannel('tsundokuExtensionBridge');

  TsundokuSourceMethods(Source source) : source = source as TSource;

  Map<String, dynamic> _mediaToJson(DMedia media) => {
        'title': media.title,
        'url': media.url,
        'thumbnail_url': media.cover,
        'description': media.description,
        'author': media.author,
        'artist': media.artist,
        'genre': media.genre,
      };

  Map<String, dynamic> _episodeToJson(DEpisode episode) => {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      };

  Future<dynamic> _invoke(String method, Map<String, dynamic> args) async {
    if (Platform.isAndroid) {
      return await platform.invokeMethod(method, args);
    }
    return await BridgeDispatcher().invokeMethod(method, args);
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final result = await _invoke('getDetail', {
      'sourceId': source.id,
      'isAnime': false,
      'media': jsonEncode(_mediaToJson(media)),
    });

    final map = result is String
        ? jsonDecode(result) as Map<String, dynamic>
        : Map<String, dynamic>.from(result as Map);

    return await compute(DMedia.fromJson, map);
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    final result = await _invoke('getPopular', {
      'sourceId': source.id,
      'isAnime': false,
      'page': page,
    });

    final map = result is String
        ? jsonDecode(result) as Map<String, dynamic>
        : Map<String, dynamic>.from(result as Map);

    return await compute(Pages.fromJson, map);
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    final result = await _invoke('getLatestUpdates', {
      'sourceId': source.id,
      'isAnime': false,
      'page': page,
    });

    final map = result is String
        ? jsonDecode(result) as Map<String, dynamic>
        : Map<String, dynamic>.from(result as Map);

    return await compute(Pages.fromJson, map);
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters,
      {SourceParams? parameters}) async {
    final result = await _invoke('search', {
      'sourceId': source.id,
      'isAnime': false,
      'query': query,
      'page': page,
    });

    final map = result is String
        ? jsonDecode(result) as Map<String, dynamic>
        : Map<String, dynamic>.from(result as Map);

    return await compute(Pages.fromJson, map);
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
          {SourceParams? parameters}) async =>
      const [];

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
          {SourceParams? parameters}) async =>
      const [];

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) async {
    final ep = DEpisode(
      name: chapterTitle,
      url: chapterId,
      episodeNumber: '1',
    );
    final result = await _invoke('getNovelContent', {
      'sourceId': source.id,
      'episode': jsonEncode(_episodeToJson(ep)),
    });

    if (result is List) {
      return result.join('\n');
    }
    if (result is String) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is List) {
          return decoded.join('\n');
        }
        return decoded?.toString() ?? result;
      } catch (_) {
        return result;
      }
    }
    return result?.toString();
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    final result = await _invoke('getPreference', {
      'sourceId': source.id,
      'isAnime': false,
    });

    final list = result is String
        ? jsonDecode(result) as List<dynamic>
        : result as List<dynamic>;

    return list
        .map((e) => mapToSourcePreference(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    final res = await _invoke('saveSourcePreference', {
      'sourceId': source.id,
      'key': pref.key,
      'value': jsonEncode({'value': value}),
    });
    return res == true || res == 'true';
  }

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<List<dynamic>> getFilterList() async => const [];
}
