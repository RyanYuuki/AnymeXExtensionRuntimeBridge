import '../../../Models/Source.dart';

class SSource extends Source {
  String? sourceCode;
  String? sourceCodeUrl;

  SSource({
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
    this.sourceCode,
    this.sourceCodeUrl,
  });

  factory SSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    return SSource(
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
      sourceCode: json['sourceCode'],
      sourceCodeUrl: json['sourceCodeUrl'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();

    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;

    return json;
  }
}
