import '../../../Models/Source.dart';

class ASource extends Source {
  String? pkgName;
  String? apkName;

  ASource({
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
    this.pkgName,
    this.apkName,
  });
  factory ASource.fromJson(Map<String, dynamic> json) {
    return ASource(
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
      itemType: ItemType.values[json['itemType'] ?? 0],
      pkgName: json['pkgName'],
      apkName: json['apkName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkUrl'] = apkName;
    map['pkgName'] = pkgName;
    return map;
  }

  String? get apkUrl {
    if (apkName == null || apkName!.isEmpty) return null;
    if (iconUrl == null || iconUrl!.isEmpty) return null;

    final baseUrl = iconUrl!.replaceFirst('icon/', 'apk/');
    final lastSlash = baseUrl.lastIndexOf('/');
    if (lastSlash == -1) return "";

    final cleanedUrl = baseUrl.substring(0, lastSlash);
    return '$cleanedUrl/$apkName';
  }
}
