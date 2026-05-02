import 'package:flutter/foundation.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourceParams.dart';
import '../../Models/SourcePreference.dart' as s;
import '../../Models/Video.dart';
import 'Eval/dart/model/m_manga.dart';
import 'Eval/dart/model/source_preference.dart';
import 'Models/Source.dart';
import 'Util/ChapterRecognition.dart';
import 'Util/extension_preferences_providers.dart';
import 'Util/get_source_preference.dart';
import 'Util/lib.dart';

class MangayomiSourceMethods implements SourceMethods {
  @override
  final MSource source;

  MangayomiSourceMethods(Source source) : source = source as MSource;

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    try {
      final data = await getExtensionService(source).getDetail(media.url!);

      DMedia createMediaData(Map<String, dynamic> args) {
        final media = args['media'] as DMedia;
        final data = args['data'] as MManga;

        final episodes = data.chapters
            ?.where((e) => e.name != null && e.url != null)
            .map(
              (e) => DEpisode(
                name: e.name!,
                url: e.url!,
                episodeNumber: ChapterRecognition.parseChapterNumber(
                  media.title ?? '',
                  e.name!,
                ).toString(),
                dateUpload: e.dateUpload,
                scanlator: e.scanlator,
              ),
            )
            .toList();
        return DMedia(
          title: media.title,
          url: media.url,
          cover: media.cover,
          description: data.description,
          artist: data.artist,
          author: data.author,
          genre: data.genre,
          episodes: episodes,
        );
      }

      final mediaData = await compute(createMediaData, {
        'media': media,
        'data': data,
      });
      return mediaData;
    } catch (e, st) {
      Logger.log("Failed to get detail: $e - $st", show: true);
      throw Exception('Failed to get detail: $e');
    }
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    final data = await getExtensionService(source).getLatestUpdates(page);

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    final data = await getExtensionService(source).getPopular(page);

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<Pages> search(String query, int page, List filters,
      {SourceParams? parameters}) async {
    final data = await getExtensionService(source).search(query, page, filters);

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    try {
      final data = await getExtensionService(source).getPageList(episode.url!);
      if (data == null) return [];

      return data.map((e) => PageUrl(e.url, headers: e.headers)).toList();
    } catch (e) {
      Logger.log("Mangayomi: getPageList failed: $e");
      return [];
    }
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async {
    try {
      final data = await getExtensionService(source).getVideoList(episode.url!);
      if (data == null) return [];

      return data.map((e) {
        return Video(
          e.quality,
          e.url,
          e.quality,
          headers: e.headers,
          audios: e.audios?.map((a) => Track(file: a.file, label: a.label)).toList(),
          subtitles: e.subtitles?.map((s) => Track(file: s.file, label: s.label)).toList(),
        );
      }).toList();
    } catch (e, st) {
      Logger.log("Mangayomi: getVideoList failed: $e\n$st");
      return [];
    }
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) async {
    try {
      final data = await getExtensionService(source)
          .getHtmlContent(chapterTitle, chapterId);

      return data;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<s.SourcePreference>> getPreference() async {
    String getType(SourcePreference pref) {
      if (pref.checkBoxPreference != null) {
        return "checkbox";
      } else if (pref.listPreference != null) {
        return "list";
      } else if (pref.multiSelectListPreference != null) {
        return "multi_select";
      } else if (pref.switchPreferenceCompat != null) {
        return "switch";
      } else if (pref.editTextPreference != null) {
        return "text";
      } else {
        return "other";
      }
    }

    try {
      final data = getSourcePreference(source: source)
          .map((e) => getSourcePreferenceEntry(e.key!, source.id!))
          .toList();
      return data
          .map(
            (p) => s.SourcePreference.fromJson(p.toJson())..type = getType(p),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> setPreference(s.SourcePreference pref, value) async {
    var data = SourcePreference.fromJson(pref.toJson())
      ..sourceId = extractSourceId(source.id!);
    if (data.listPreference != null) {
      data.listPreference?.valueIndex =
          data.listPreference?.entryValues?.indexOf(value ?? '');
    } else if (data.checkBoxPreference != null) {
      data.checkBoxPreference?.value = value;
    } else if (data.switchPreferenceCompat != null) {
      data.switchPreferenceCompat?.value = value;
    } else if (data.editTextPreference != null) {
      data.editTextPreference?.value = value;
    } else if (data.multiSelectListPreference != null) {
      data.multiSelectListPreference?.values = value;
    }
    setPreferenceSetting(data, source);
    return true;
  }

  List<DMedia> _mapMediaList(List<dynamic> list) {
    return list
        .map(
          (e) => DMedia(
            title: e.name,
            url: e.link,
            cover: e.imageUrl,
            description: e.description,
            artist: e.artist,
          ),
        )
        .toList();
  }

  @override
  Stream<Video>? getVideoListStream(DEpisode episode,
          {SourceParams? parameters}) =>
      null;

  @override
  Future<void> cancelRequest(String token) {
    throw UnimplementedError();
  }
}
