import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourceParams.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import 'Models/LegadoSource.dart';
import 'RuleEngine/LegadoRuleEngine.dart';

void _log(String msg) {
  // ignore: avoid_print
  print('[Legado] $msg');
}

class LegadoSourceMethods extends SourceMethods {
  @override
  final LegadoSource source;

  LegadoSourceMethods(Source source) : source = source as LegadoSource;

  static final http.Client _client = http.Client();

  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    if (source.header != null && source.header!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(source.header!);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            headers[k.toString()] = v.toString();
          });
        }
      } catch (_) {}
    }

    if (extra != null) {
      headers.addAll(extra);
    }

    return headers;
  }

  Future<String> _fetch(String url, {Map<String, String>? customHeaders}) async {
    String actualUrl = url;
    String method = 'GET';
    String? body;
    Map<String, String> reqHeaders = _buildHeaders(customHeaders);

    // Legado format: url,{"method":"POST","body":"...","headers":{...}}
    final optionsIndex = url.indexOf(',{');
    if (optionsIndex != -1) {
      actualUrl = url.substring(0, optionsIndex);
      final jsonStr = url.substring(optionsIndex + 1);
      try {
        final opts = jsonDecode(jsonStr);
        if (opts is Map) {
          if (opts['method'] != null) method = opts['method'].toString().toUpperCase();
          if (opts['body'] != null) body = opts['body'].toString();
          if (opts['headers'] is Map) {
            (opts['headers'] as Map).forEach((k, v) {
              reqHeaders[k.toString()] = v.toString();
            });
          }
        }
      } catch (_) {}
    }

    final uri = Uri.parse(actualUrl);
    http.Response res;
    if (method == 'POST') {
      res = await _client.post(uri, headers: reqHeaders, body: body);
    } else {
      res = await _client.get(uri, headers: reqHeaders);
    }

    if (res.statusCode >= 200 && res.statusCode < 400) {
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } else {
      throw Exception("HTTP ${res.statusCode} for $actualUrl");
    }
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters,
      {SourceParams? parameters}) async {
    try {
      final searchUrlTemplate = source.searchUrl;
      if (searchUrlTemplate == null || searchUrlTemplate.trim().isEmpty) {
        return Pages(list: [], hasNextPage: false);
      }

      final url = LegadoRuleEngine.buildUrl(
        urlTemplate: searchUrlTemplate,
        baseUrl: source.baseUrl ?? '',
        query: query,
        page: page,
      );

      final html = await _fetch(url);
      final doc = LegadoRuleEngine.parseHtml(html);

      final rule = source.ruleSearch ?? source.ruleExplore;
      if (rule == null) return Pages(list: [], hasNextPage: false);

      final bookListRule = rule['bookList']?.toString();
      final elements = LegadoRuleEngine.selectElements(doc, bookListRule);

      final results = <DMedia>[];
      for (final el in elements) {
        final title = LegadoRuleEngine.extractString(el, rule['name']?.toString());
        String bookUrl = LegadoRuleEngine.extractString(el, rule['bookUrl']?.toString(), baseUrl: source.baseUrl ?? '');
        final cover = LegadoRuleEngine.extractString(el, rule['coverUrl']?.toString(), baseUrl: source.baseUrl ?? '');
        final author = LegadoRuleEngine.extractString(el, rule['author']?.toString());
        final intro = LegadoRuleEngine.extractString(el, rule['intro']?.toString());

        if (title.isNotEmpty && bookUrl.isNotEmpty) {
          results.add(DMedia(
            title: title,
            url: bookUrl,
            cover: cover.isNotEmpty ? cover : null,
            author: author.isNotEmpty ? author : null,
            description: intro.isNotEmpty ? intro : null,
          ));
        }
      }

      return Pages(list: results, hasNextPage: results.isNotEmpty);
    } catch (e, st) {
      _log("Legado search error: $e\n$st");
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    return _getExplore(page, preferPopular: true);
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    return _getExplore(page, preferPopular: false);
  }

  Future<Pages> _getExplore(int page, {required bool preferPopular}) async {
    try {
      final exploreTemplate = source.exploreUrl;
      if (exploreTemplate == null || exploreTemplate.trim().isEmpty) {
        return Pages(list: [], hasNextPage: false);
      }

      // ExploreUrl can contain multiple sections e.g. "Latest::url1\nHot::url2"
      final lines = exploreTemplate
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) return Pages(list: [], hasNextPage: false);

      String targetLine = lines.first;
      if (preferPopular) {
        final hotLine = lines.firstWhere(
          (l) => l.toLowerCase().contains('hot') || l.toLowerCase().contains('popular'),
          orElse: () => lines.length > 1 ? lines[1] : lines.first,
        );
        targetLine = hotLine;
      } else {
        final latestLine = lines.firstWhere(
          (l) => l.toLowerCase().contains('latest') || l.toLowerCase().contains('update'),
          orElse: () => lines.first,
        );
        targetLine = latestLine;
      }

      // Strip title prefix (e.g. "Hot::/novel-list/...")
      String urlPart = targetLine;
      if (targetLine.contains('::')) {
        urlPart = targetLine.substring(targetLine.indexOf('::') + 2).trim();
      }

      final url = LegadoRuleEngine.buildUrl(
        urlTemplate: urlPart,
        baseUrl: source.baseUrl ?? '',
        page: page,
      );

      final html = await _fetch(url);
      final doc = LegadoRuleEngine.parseHtml(html);

      final rule = source.ruleExplore ?? source.ruleSearch;
      if (rule == null) return Pages(list: [], hasNextPage: false);

      final bookListRule = rule['bookList']?.toString();
      final elements = LegadoRuleEngine.selectElements(doc, bookListRule);

      final results = <DMedia>[];
      for (final el in elements) {
        final title = LegadoRuleEngine.extractString(el, rule['name']?.toString());
        String bookUrl = LegadoRuleEngine.extractString(el, rule['bookUrl']?.toString(), baseUrl: source.baseUrl ?? '');
        final cover = LegadoRuleEngine.extractString(el, rule['coverUrl']?.toString(), baseUrl: source.baseUrl ?? '');
        final author = LegadoRuleEngine.extractString(el, rule['author']?.toString());
        final intro = LegadoRuleEngine.extractString(el, rule['intro']?.toString());

        if (title.isNotEmpty && bookUrl.isNotEmpty) {
          results.add(DMedia(
            title: title,
            url: bookUrl,
            cover: cover.isNotEmpty ? cover : null,
            author: author.isNotEmpty ? author : null,
            description: intro.isNotEmpty ? intro : null,
          ));
        }
      }

      return Pages(list: results, hasNextPage: results.isNotEmpty);
    } catch (e, st) {
      _log("Legado getExplore error: $e\n$st");
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    try {
      final bookUrl = media.url;
      if (bookUrl == null || bookUrl.isEmpty) return media;

      final fullBookUrl = LegadoRuleEngine.resolveUrl(source.baseUrl ?? '', bookUrl);
      final html = await _fetch(fullBookUrl);
      final doc = LegadoRuleEngine.parseHtml(html);

      final ruleBook = source.ruleBookInfo ?? {};

      final title = LegadoRuleEngine.extractString(doc, ruleBook['name']?.toString());
      final cover = LegadoRuleEngine.extractString(doc, ruleBook['coverUrl']?.toString(), baseUrl: source.baseUrl ?? '');
      final author = LegadoRuleEngine.extractString(doc, ruleBook['author']?.toString());
      final intro = LegadoRuleEngine.extractString(doc, ruleBook['intro']?.toString());
      final kind = LegadoRuleEngine.extractString(doc, ruleBook['kind']?.toString());

      List<String>? genres;
      if (kind.isNotEmpty) {
        genres = kind
            .split(RegExp(r'[,/;\n\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      // Determine Table of Contents (TOC / chapters)
      dynamic tocDoc = doc;
      final rawTocUrl = ruleBook['tocUrl']?.toString();
      if (rawTocUrl != null && rawTocUrl.isNotEmpty) {
        // Interpolate any {{@@selector@attr}} patterns using the book detail doc
        String resolvedTocUrl = rawTocUrl;
        final templateMatches = RegExp(r'\{\{@@([^}]+)\}\}').allMatches(rawTocUrl);
        for (final m in templateMatches) {
          final selector = m.group(1)!;
          final val = LegadoRuleEngine.extractString(doc, selector);
          resolvedTocUrl = resolvedTocUrl.replaceFirst(m.group(0)!, val);
        }

        resolvedTocUrl = LegadoRuleEngine.resolveUrl(source.baseUrl ?? '', resolvedTocUrl);
        try {
          final tocHtml = await _fetch(resolvedTocUrl);
          tocDoc = LegadoRuleEngine.parseHtml(tocHtml);
        } catch (e) {
          _log("Legado toc fetch failed: $e, using book doc");
        }
      }

      final ruleToc = source.ruleToc ?? {};
      final chapterElements = LegadoRuleEngine.selectElements(tocDoc, ruleToc['chapterList']?.toString());

      final chapters = <DEpisode>[];
      int epNum = 1;
      for (final el in chapterElements) {
        final chName = LegadoRuleEngine.extractString(el, ruleToc['chapterName']?.toString() ?? 'text');
        String chUrl = LegadoRuleEngine.extractString(el, ruleToc['chapterUrl']?.toString() ?? 'href', baseUrl: source.baseUrl ?? '');

        if (chUrl.isNotEmpty) {
          chapters.add(DEpisode(
            name: chName.isNotEmpty ? chName : 'Chapter $epNum',
            url: chUrl,
            episodeNumber: epNum.toString(),
          ));
          epNum++;
        }
      }

      return DMedia(
        title: title.isNotEmpty ? title : media.title,
        url: fullBookUrl,
        cover: cover.isNotEmpty ? cover : media.cover,
        author: author.isNotEmpty ? author : media.author,
        description: intro.isNotEmpty ? intro : media.description,
        genre: genres ?? media.genre,
        episodes: chapters.isNotEmpty ? chapters : media.episodes,
      );
    } catch (e, st) {
      _log("Legado getDetail error: $e\n$st");
      return media;
    }
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) async {
    try {
      String chapterUrl = chapterId;
      if (!chapterUrl.startsWith('http://') && !chapterUrl.startsWith('https://')) {
        chapterUrl = LegadoRuleEngine.resolveUrl(source.baseUrl ?? '', chapterUrl);
      }

      final html = await _fetch(chapterUrl);
      final doc = LegadoRuleEngine.parseHtml(html);

      final ruleContent = source.ruleContent ?? {};
      final contentSelector = ruleContent['content']?.toString() ?? 'p@text';

      String content = LegadoRuleEngine.extractString(doc, contentSelector);

      final replaceRegex = ruleContent['replaceRegex']?.toString();
      if (replaceRegex != null && replaceRegex.isNotEmpty) {
        final reps = _parseReplacements(replaceRegex);
        for (final rep in reps) {
          if (rep.isEmpty) continue;
          final pat = rep[0];
          final repl = rep.length > 1 ? rep[1] : '';
          try {
            content = content.replaceAll(RegExp(pat, multiLine: true), repl);
          } catch (_) {}
        }
      }

      return content.trim();
    } catch (e, st) {
      _log("Legado getNovelContent error: $e\n$st");
      return null;
    }
  }

  static List<List<String>> _parseReplacements(String raw) {
    String clean = raw.trim();
    if (clean.startsWith('##')) clean = clean.substring(2);
    if (clean.endsWith('###')) clean = clean.substring(0, clean.length - 3);

    final list = <List<String>>[];
    final blocks = clean.split('###');
    for (final block in blocks) {
      if (block.isEmpty) continue;
      final parts = block.split('##');
      if (parts.length == 1) {
        list.add([parts[0], '']);
      } else {
        list.add([parts[0], parts[1]]);
      }
    }
    return list;
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    if (episode.url != null && episode.url!.isNotEmpty) {
      return [PageUrl(episode.url!)];
    }
    return [];
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async => [];

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<List<SourcePreference>> getPreference() async => [];

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async => true;
}
