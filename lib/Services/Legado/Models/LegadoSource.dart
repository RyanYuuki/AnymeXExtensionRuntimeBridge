import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../../../Models/Source.dart';

class LegadoSource extends Source {
  String? bookSourceName;
  String? bookSourceUrl;
  String? bookSourceGroup;
  int? bookSourceType;
  String? bookSourceComment;
  String? searchUrl;
  String? exploreUrl;
  String? header;
  Map<String, dynamic>? ruleSearch;
  Map<String, dynamic>? ruleExplore;
  Map<String, dynamic>? ruleBookInfo;
  Map<String, dynamic>? ruleToc;
  Map<String, dynamic>? ruleContent;
  int? weight;

  LegadoSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.managerId,
    super.hasUpdate,
    super.supportsLatest = true,
    super.supportsPopular = true,
    this.bookSourceName,
    this.bookSourceUrl,
    this.bookSourceGroup,
    this.bookSourceType,
    this.bookSourceComment,
    this.searchUrl,
    this.exploreUrl,
    this.header,
    this.ruleSearch,
    this.ruleExplore,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.weight,
  });

  static String generateId(String url, [String? name]) {
    final input = '$url|${name ?? ''}';
    return md5.convert(utf8.encode(input)).toString();
  }

  factory LegadoSource.fromLegadoJson(Map<String, dynamic> json, {String? repoUrl}) {
    final rawName = (json['bookSourceName'] ?? json['name'] ?? '').toString();
    final rawUrl = (json['bookSourceUrl'] ?? json['baseUrl'] ?? '').toString();
    final rawGroup = (json['bookSourceGroup'] ?? json['lang'] ?? '').toString();
    final sourceId = json['id']?.toString() ?? generateId(rawUrl, rawName);

    Map<String, dynamic>? parseRuleMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String && value.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return null;
    }

    String? headerStr;
    if (json['header'] != null) {
      if (json['header'] is String) {
        headerStr = json['header'];
      } else {
        try {
          headerStr = jsonEncode(json['header']);
        } catch (_) {}
      }
    }

    final hasExplore = json['exploreUrl'] != null && json['exploreUrl'].toString().trim().isNotEmpty;

    String? resolvedIcon;
    final rawIcon = (json['iconUrl'] ?? json['bookSourceIcon'])?.toString().trim();
    if (rawIcon != null && rawIcon.isNotEmpty) {
      if (rawIcon.startsWith('http://') || rawIcon.startsWith('https://')) {
        resolvedIcon = rawIcon;
      } else if (rawIcon.startsWith('//')) {
        resolvedIcon = 'https:$rawIcon';
      } else if (rawUrl.isNotEmpty) {
        try {
          resolvedIcon = Uri.parse(rawUrl).resolve(rawIcon).toString();
        } catch (_) {}
      }
    }

    if (resolvedIcon == null || resolvedIcon.isEmpty) {
      if (rawUrl.isNotEmpty) {
        try {
          final host = Uri.tryParse(rawUrl)?.host;
          if (host != null && host.isNotEmpty) {
            resolvedIcon = 'https://www.google.com/s2/favicons?domain=$host&sz=128';
          }
        } catch (_) {}
      }
    }

    return LegadoSource(
      id: sourceId,
      name: rawName,
      baseUrl: rawUrl,
      lang: rawGroup.isNotEmpty ? rawGroup : 'all',
      isNsfw: false,
      iconUrl: resolvedIcon,
      version: json['version']?.toString() ?? '1.0.0',
      versionLast: json['versionLast']?.toString() ?? '1.0.0',
      itemType: ItemType.novel,
      repo: repoUrl ?? json['repo'],
      managerId: 'legado',
      hasUpdate: false,
      supportsLatest: hasExplore,
      supportsPopular: hasExplore,
      bookSourceName: rawName,
      bookSourceUrl: rawUrl,
      bookSourceGroup: rawGroup,
      bookSourceType: json['bookSourceType'] is int ? json['bookSourceType'] : int.tryParse(json['bookSourceType']?.toString() ?? '0') ?? 0,
      bookSourceComment: json['bookSourceComment']?.toString(),
      searchUrl: json['searchUrl']?.toString(),
      exploreUrl: json['exploreUrl']?.toString(),
      header: headerStr,
      ruleSearch: parseRuleMap(json['ruleSearch']),
      ruleExplore: parseRuleMap(json['ruleExplore']),
      ruleBookInfo: parseRuleMap(json['ruleBookInfo']),
      ruleToc: parseRuleMap(json['ruleToc']),
      ruleContent: parseRuleMap(json['ruleContent']),
      weight: json['weight'] is int ? json['weight'] : int.tryParse(json['weight']?.toString() ?? '0'),
    );
  }

  factory LegadoSource.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('bookSourceUrl') || json.containsKey('bookSourceName') || json.containsKey('ruleSearch')) {
      return LegadoSource.fromLegadoJson(json);
    }

    final base = Source.fromJson(json);
    return LegadoSource(
      id: base.id,
      name: base.name,
      baseUrl: base.baseUrl,
      lang: base.lang,
      isNsfw: base.isNsfw,
      iconUrl: base.iconUrl,
      version: base.version,
      versionLast: base.versionLast,
      itemType: ItemType.novel,
      repo: base.repo,
      managerId: 'legado',
      hasUpdate: base.hasUpdate,
      supportsLatest: base.supportsLatest ?? true,
      supportsPopular: base.supportsPopular ?? true,
      bookSourceName: json['bookSourceName'] ?? base.name,
      bookSourceUrl: json['bookSourceUrl'] ?? base.baseUrl,
      bookSourceGroup: json['bookSourceGroup'] ?? base.lang,
      bookSourceType: json['bookSourceType'],
      bookSourceComment: json['bookSourceComment'],
      searchUrl: json['searchUrl'],
      exploreUrl: json['exploreUrl'],
      header: json['header'],
      ruleSearch: json['ruleSearch'] != null ? Map<String, dynamic>.from(json['ruleSearch']) : null,
      ruleExplore: json['ruleExplore'] != null ? Map<String, dynamic>.from(json['ruleExplore']) : null,
      ruleBookInfo: json['ruleBookInfo'] != null ? Map<String, dynamic>.from(json['ruleBookInfo']) : null,
      ruleToc: json['ruleToc'] != null ? Map<String, dynamic>.from(json['ruleToc']) : null,
      ruleContent: json['ruleContent'] != null ? Map<String, dynamic>.from(json['ruleContent']) : null,
      weight: json['weight'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['bookSourceName'] = bookSourceName;
    json['bookSourceUrl'] = bookSourceUrl;
    json['bookSourceGroup'] = bookSourceGroup;
    json['bookSourceType'] = bookSourceType;
    json['bookSourceComment'] = bookSourceComment;
    json['searchUrl'] = searchUrl;
    json['exploreUrl'] = exploreUrl;
    json['header'] = header;
    json['ruleSearch'] = ruleSearch;
    json['ruleExplore'] = ruleExplore;
    json['ruleBookInfo'] = ruleBookInfo;
    json['ruleToc'] = ruleToc;
    json['ruleContent'] = ruleContent;
    json['weight'] = weight;
    return json;
  }
}
