import '../../../Models/Source.dart';

class PaperbackSource extends Source {
  String? sourceCode;
  String? sourceCodeUrl;
  String? description;
  String? contentRating;
  List<int>? capabilities;
  String? author;

  PaperbackSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType = ItemType.manga,
    super.repo,
    super.managerId = 'paperback',
    super.hasUpdate,
    super.supportsLatest = true,
    super.supportsPopular = true,
    this.sourceCode,
    this.sourceCodeUrl,
    this.description,
    this.contentRating,
    this.capabilities,
    this.author,
  });

  factory PaperbackSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    List<int>? caps;
    if (json['capabilities'] is List) {
      caps = (json['capabilities'] as List).map((e) => int.tryParse(e.toString()) ?? 0).toList();
    }

    String? devAuthor;
    if (json['author'] != null) {
      devAuthor = json['author'].toString();
    } else if (json['developers'] is List && (json['developers'] as List).isNotEmpty) {
      final firstDev = (json['developers'] as List).first;
      if (firstDev is Map) {
        devAuthor = firstDev['name']?.toString();
      } else if (firstDev is String) {
        devAuthor = firstDev;
      }
    }

    final rating = json['contentRating']?.toString();
    final nsfw = base.isNsfw ?? (rating == 'ADULT' || rating == 'MATURE');

    return PaperbackSource(
      id: base.id,
      name: base.name,
      baseUrl: base.baseUrl,
      lang: base.lang,
      isNsfw: nsfw,
      iconUrl: base.iconUrl,
      version: base.version,
      versionLast: base.versionLast,
      itemType: ItemType.manga,
      repo: base.repo,
      managerId: 'paperback',
      hasUpdate: base.hasUpdate,
      supportsLatest: base.supportsLatest ?? true,
      supportsPopular: base.supportsPopular ?? true,
      sourceCode: json['sourceCode'],
      sourceCodeUrl: json['sourceCodeUrl'],
      description: json['description']?.toString(),
      contentRating: rating,
      capabilities: caps,
      author: devAuthor,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();

    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;
    json['description'] = description;
    json['contentRating'] = contentRating;
    json['capabilities'] = capabilities;
    json['author'] = author;
    json['managerId'] = 'paperback';

    return json;
  }
}
