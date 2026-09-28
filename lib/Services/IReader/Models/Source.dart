import '../../../Models/Source.dart';
import '../../Shared/PackagedSource.dart';

class ISource extends PackagedSource {
  bool? isShared;
  List<ISource>? langs;

  ISource({
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
    super.apkName,
    super.apkUrlOverride,
    super.jarUrl,
    super.apkPath,
    super.pkgName,
    this.isShared,
    this.langs,
  });

  factory ISource.fromJson(Map<String, dynamic> json) {
    return ISource(
      id: json['id']?.toString().toLowerCase() ??
          json['name']?.toString().toLowerCase() ??
          '',
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['language'] ?? json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'] ?? false,
      version: json['version']?.toString() ?? "1.0.0",
      versionLast: json['versionLast'] ?? "1.0.0",
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.novel,
      apkName: json['apkName'],
      apkUrlOverride: json['apkUrlOverride'] ?? json['apkUrl'],
      jarUrl: json['jarUrl'],
      apkPath: json['apkPath'],
      pkgName: json['pkgName'],
      isShared: json['isShared'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkName'] = apkName;
    map['apkPath'] = apkPath;
    map['pkgName'] = pkgName;
    map['apkUrlOverride'] = apkUrlOverride;
    map['jarUrl'] = jarUrl;
    map['isShared'] = isShared;
    return map;
  }
}

class IdSource extends ISource {
  IdSource({
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
    super.apkName,
    super.apkUrlOverride,
    super.jarUrl,
    super.apkPath,
    super.pkgName,
    super.isShared,
    super.langs,
  });

  factory IdSource.fromJson(Map<String, dynamic> json) {
    return IdSource(
      id: json['id']?.toString().toLowerCase() ??
          json['name']?.toString().toLowerCase() ??
          '',
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['language'] ?? json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'] ?? false,
      version: json['version']?.toString() ?? "1.0.0",
      versionLast: json['versionLast'] ?? "1.0.0",
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.novel,
      apkName: json['apkName'],
      apkUrlOverride: json['apkUrlOverride'] ?? json['apkUrl'],
      jarUrl: json['jarUrl'],
      apkPath: json['apkPath'],
      pkgName: json['pkgName'],
      isShared: json['isShared'],
    );
  }
}
