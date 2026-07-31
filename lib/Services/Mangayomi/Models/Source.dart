import '../../../anymex_extension_runtime_bridge.dart';
import '../Eval/dart/model/m_source.dart' as m;
import '../Util/string_extensions.dart';

class MSource extends Source {
  String? sourceCode;

  String? sourceCodeUrl;

  String? headers;

  SourceCodeLanguage sourceCodeLanguage = SourceCodeLanguage.dart;

  MSource({
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
    super.hasUpdate,
    super.supportsLatest = false,
    super.supportsPopular = false,
    this.sourceCodeUrl,
    this.sourceCode,
    this.headers,
    this.sourceCodeLanguage = SourceCodeLanguage.dart,
  });

  factory MSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    final isLnReader = json['site'] != null && json['url'] != null && json['sourceCodeLanguage'] == null;

    return MSource(
      id: base.id,
      name: base.name,
      baseUrl: base.baseUrl,
      lang: base.lang,
      isNsfw: base.isNsfw,
      iconUrl: base.iconUrl,
      version: base.version,
      versionLast: base.versionLast,
      itemType: base.itemType,
      repo: base.repo,
      hasUpdate: base.hasUpdate,
      supportsLatest: base.supportsLatest ?? false,
      supportsPopular: base.supportsPopular ?? false,
      sourceCode: json['sourceCode'],
      sourceCodeUrl: json['sourceCodeUrl'] ?? json['url'],
      headers: json['headers'],
      sourceCodeLanguage: isLnReader
          ? SourceCodeLanguage.lnreader
          : SourceCodeLanguage.values[json['sourceCodeLanguage'] ?? 0],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;
    json['headers'] = headers;
    json['sourceCodeLanguage'] = sourceCodeLanguage.index;
    return json;
  }

  // bool get isTorrent => (typeSource?.toLowerCase() ?? "") == "torrent";

  m.MSource toMSource() {
    return m.MSource(
      id: id?.toNullInt() ?? 0,
      name: name,
      hasCloudflare: false,
      isFullData: true,
      lang: lang,
      baseUrl: baseUrl,
    );
  }
}

enum SourceCodeLanguage { dart, javascript, lnreader }
