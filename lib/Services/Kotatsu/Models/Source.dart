import '../../../Models/Source.dart';

class KotatsuSource extends Source {
  String? jarName;
  String? pkgName;

  KotatsuSource({
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
    this.jarName,
    this.pkgName,
  });

  factory KotatsuSource.fromJson(Map<String, dynamic> json) {
    return KotatsuSource(
      id: json['id']?.toString(),
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'],
      version: json['version'],
      versionLast: json['versionLast'],
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      supportsLatest: json['supportsLatest'] ?? false,
      supportsPopular: json['supportsPopular'] ?? false,
      itemType: ItemType.values[json['itemType'] ?? 0],
      jarName: json['jarName'],
      pkgName: json['pkgName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['jarName'] = jarName;
    map['pkgName'] = pkgName;
    return map;
  }
}
