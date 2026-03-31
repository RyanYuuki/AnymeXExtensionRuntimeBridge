import '../Models/DEpisode.dart';
import '../Models/DMedia.dart';
import '../Models/Page.dart';
import '../Models/Pages.dart';
import '../Models/Source.dart';
import '../Models/SourceParams.dart';
import '../Models/SourcePreference.dart';
import '../Models/Video.dart';

abstract class SourceMethods {
  Source get source;
  
  SourceMethods();

  Future<Pages> getPopular(int page, {SourceParams? parameters});

  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters});

  Future<Pages> search(String query, int page, List<dynamic> filters,
      {SourceParams? parameters});

  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters});

  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters});

  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters});

  Stream<Video>? getVideoListStream(DEpisode episode,
          {SourceParams? parameters}) =>
      null;

  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters});

  Future<void> cancelRequest(String token);

  Future<List<SourcePreference>> getPreference();

  Future<bool> setPreference(SourcePreference pref, dynamic value);
}
