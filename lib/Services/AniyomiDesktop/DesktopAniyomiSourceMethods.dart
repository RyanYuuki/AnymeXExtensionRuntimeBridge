import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../Logger.dart';
import '../../anymex_extension_runtime_bridge.dart';
import '../Aniyomi/Models/Source.dart';
import '../Mangayomi/Eval/dart/model/filter.dart';
import '../../Runtime/Bridge/BridgeDispatcher.dart';
import '../../Torrent/torrent_stream_resolver.dart';

class DesktopAniyomiSourceMethods extends SourceMethods {
  @override
  final ASource source;

  DesktopAniyomiSourceMethods(Source source) : source = source as ASource;

  bool get isAnime => source.itemType == ItemType.anime;

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final result = await BridgeDispatcher().invokeMethod('getDetail', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'media': {
        'title': media.title,
        'url': media.url,
        'thumbnail_url': media.cover,
        'description': media.description,
        'author': media.author,
        'artist': media.artist,
        'genre': media.genre,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    final data = await compute(
      DMedia.fromJson,
      Map<String, dynamic>.from(result as Map),
    );

    print("AnymeX Bridge: getDetail result: ${data.toJson()}");

    return data;
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    final result = await BridgeDispatcher().invokeMethod('getLatestUpdates', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    final result = await BridgeDispatcher().invokeMethod('getPopular', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async {
    final result = await BridgeDispatcher().invokeMethod('getVideoList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    print("AnymeX Bridge: getVideoList result: $result");

    if (result == null || result is! List) {
      if (result is Map && result.containsKey('error')) {
        Logger.log("AnymeX Bridge: getVideoList failed: ${result['error']}");
      } else {
        Logger.log("AnymeX Bridge: getVideoList returned invalid data: $result");
      }
      return [];
    }

    return await compute(parseVideos, List<dynamic>.from(result));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    final result = await BridgeDispatcher().invokeMethod('getPageList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    if (result is Map && result.containsKey('error')) {
      Logger.log("AnymeX Bridge: getPageList failed: ${result['error']}");
      return [];
    }

    return compute(parsePageUrls, List<dynamic>.from(result as List));
  }

  @override
  Future<Pages> search(String query, int page, List filters,
      {SourceParams? parameters}) async {
    final mappedFilters = filters.map((f) {
      if (f is Map) return f;
      return _mapClassToAniyomiFilter(f);
    }).where((f) => f != null).toList();

    final result = await BridgeDispatcher().invokeMethod('search', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'query': query,
      'page': page,
      'filters': mappedFilters,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<List<dynamic>> getFilterList() async {
    try {
      final result = await BridgeDispatcher().invokeMethod('getFilterList', {
        'sourceId': source.id,
        'isAnime': isAnime,
      });
      List<dynamic> list;
      if (result is String) {
        list = jsonDecode(result) as List<dynamic>;
      } else {
        list = result as List<dynamic>;
      }
      return list
          .map((f) => _mapAniyomiFilterToClass(Map<dynamic, dynamic>.from(f)))
          .where((f) => f != null)
          .toList();
    } catch (e) {
      Logger.log('DesktopAniyomiSourceMethods getFilterList error: $e');
      return [];
    }
  }

  dynamic _mapAniyomiFilterToClass(Map<dynamic, dynamic> map) {
    final name = map['name'] as String? ?? '';
    final type = map['type'] as String? ?? '';
    final state = map['state'];
    final values = map['values'] as List<dynamic>?;

    switch (type) {
      case 'Header':
        return HeaderFilter(name, 'HeaderFilter', type: '');
      case 'Separator':
        return SeparatorFilter('SeparatorFilter', type: '');
      case 'CheckBox':
        return CheckBoxFilter(
          '', name, name, 'CheckBox',
          state: state is bool ? state : false,
        );
      case 'TriState':
        return TriStateFilter(
          '', name, name, 'TriState',
          state: state is int ? state : 0,
        );
      case 'Select':
        final selectOptions = values
                ?.map((v) => SelectFilterOption(v.toString(), v.toString(), 'SelectOption'))
                .toList() ??
            [];
        return SelectFilter(
          '', name, state is int ? state : 0, selectOptions, 'SelectFilter',
        );
      case 'Sort':
        final selectOptions = values
                ?.map((v) => SelectFilterOption(v.toString(), v.toString(), 'SelectOption'))
                .toList() ??
            [];
        SortState sortState;
        if (state is Map) {
          sortState = SortState(
            state['index'] is int ? state['index'] : 0,
            state['ascending'] is bool ? state['ascending'] : true,
            'SortState',
          );
        } else {
          sortState = SortState(0, true, 'SortState');
        }
        return SortFilter(
          '', name, sortState, selectOptions, 'SortFilter',
        );
      case 'Text':
        return TextFilter(
          '', name, 'TextFilter',
          state: state is String ? state : '',
        );
      case 'Group':
        final subFilters = (state as List<dynamic>?)
                ?.map((sub) => _mapAniyomiFilterToClass(Map<dynamic, dynamic>.from(sub)))
                .where((f) => f != null)
                .toList() ??
            [];
        return GroupFilter(
          '', name, subFilters, 'GroupFilter',
        );
      default:
        return null;
    }
  }

  Map<String, dynamic>? _mapClassToAniyomiFilter(dynamic filter) {
    if (filter is HeaderFilter) {
      return {
        'name': filter.name,
        'type': 'Header',
        'state': null,
      };
    } else if (filter is SeparatorFilter) {
      return {
        'name': '',
        'type': 'Separator',
        'state': null,
      };
    } else if (filter is CheckBoxFilter) {
      return {
        'name': filter.name,
        'type': 'CheckBox',
        'state': filter.state,
      };
    } else if (filter is TriStateFilter) {
      return {
        'name': filter.name,
        'type': 'TriState',
        'state': filter.state,
      };
    } else if (filter is SelectFilter) {
      return {
        'name': filter.name,
        'type': 'Select',
        'state': filter.state,
      };
    } else if (filter is SortFilter) {
      return {
        'name': filter.name,
        'type': 'Sort',
        'state': {
          'index': filter.state.index,
          'ascending': filter.state.ascending,
        },
      };
    } else if (filter is TextFilter) {
      return {
        'name': filter.name,
        'type': 'Text',
        'state': filter.state,
      };
    } else if (filter is GroupFilter) {
      return {
        'name': filter.name,
        'type': 'Group',
        'state': filter.state.map((sub) => _mapClassToAniyomiFilter(sub)).toList(),
      };
    }
    return null;
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<PageUrl> parsePageUrls(List<dynamic> list) {
    return list
        .map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelRequest(String token) async {
    await AnymeXRuntimeBridge.cancelRequest(token);
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    try {
      final params = {
        'sourceId': source.id,
        'isAnime': isAnime,
      };
      final result = await BridgeDispatcher().invokeMethod('aniyomiGetPreferences', params);
      final List<dynamic> decoded = (result is String) ? jsonDecode(result) : result;
      return decoded
          .map((e) =>
              SourcePreference.fromAniyomiDesktopJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      Logger.log("AnymeX Bridge: Failed to get desktop preferences for ${source.name}: $e");
      return [];
    }
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    try {
      final result = await BridgeDispatcher().invokeMethod('aniyomiSavePreference', {
        'sourceId': source.id,
        'key': pref.key,
        'value': value,
        'isAnime': isAnime,
      });
      return result ?? false;
    } catch (e) {
      Logger.log("AnymeX Bridge: Failed to save desktop preference ${pref.key} for ${source.name}: $e");
      return false;
    }
  }

  @override
  Future<void> stopHttpServer() async {
    try {
      await BridgeDispatcher().invokeMethod('stopHttpServer', {
        'sourceId': source.id,
        'isAnime': isAnime,
      });
    } catch (e) {
      Logger.log("AnymeX Bridge: Failed to stop desktop http server: $e");
    }
  }
}
