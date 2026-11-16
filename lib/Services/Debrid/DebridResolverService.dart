import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../Logger.dart';
import '../../Settings/KvStore.dart';

enum DebridProviderType {
  realDebrid,
  torBox,
  premiumize,
  allDebrid,
}

class DebridResolvedLink {
  final String url;
  final String? filename;
  final int? fileSize;
  final String provider;

  DebridResolvedLink({
    required this.url,
    this.filename,
    this.fileSize,
    required this.provider,
  });
}

class DebridResolverService {
  static final http.Client _client = http.Client();

  static const String keyActiveProvider = 'debrid_active_provider';
  static const String keyRealDebridToken = 'debrid_realdebrid_key';
  static const String keyTorBoxToken = 'debrid_torbox_key';
  static const String keyPremiumizeToken = 'debrid_premiumize_key';
  static const String keyAllDebridToken = 'debrid_alldebrid_key';
  static const String keyEnabled = 'debrid_enabled';

  static bool isEnabled() {
    return KvStore.get<String>(keyEnabled) == 'true';
  }

  static void setEnabled(bool enabled) {
    KvStore.setSync(keyEnabled, enabled ? 'true' : 'false');
  }

  static String? getApiKey(DebridProviderType provider) {
    switch (provider) {
      case DebridProviderType.realDebrid:
        return KvStore.get<String>(keyRealDebridToken);
      case DebridProviderType.torBox:
        return KvStore.get<String>(keyTorBoxToken);
      case DebridProviderType.premiumize:
        return KvStore.get<String>(keyPremiumizeToken);
      case DebridProviderType.allDebrid:
        return KvStore.get<String>(keyAllDebridToken);
    }
  }

  static void setApiKey(DebridProviderType provider, String key) {
    final trimmed = key.trim();
    switch (provider) {
      case DebridProviderType.realDebrid:
        KvStore.setSync(keyRealDebridToken, trimmed);
        break;
      case DebridProviderType.torBox:
        KvStore.setSync(keyTorBoxToken, trimmed);
        break;
      case DebridProviderType.premiumize:
        KvStore.setSync(keyPremiumizeToken, trimmed);
        break;
      case DebridProviderType.allDebrid:
        KvStore.setSync(keyAllDebridToken, trimmed);
        break;
    }
  }

  static DebridProviderType getActiveProvider() {
    final raw = KvStore.get<String>(keyActiveProvider);
    if (raw == 'torbox') return DebridProviderType.torBox;
    if (raw == 'premiumize') return DebridProviderType.premiumize;
    if (raw == 'alldebrid') return DebridProviderType.allDebrid;
    return DebridProviderType.realDebrid;
  }

  static void setActiveProvider(DebridProviderType provider) {
    switch (provider) {
      case DebridProviderType.realDebrid:
        KvStore.setSync(keyActiveProvider, 'realdebrid');
        break;
      case DebridProviderType.torBox:
        KvStore.setSync(keyActiveProvider, 'torbox');
        break;
      case DebridProviderType.premiumize:
        KvStore.setSync(keyActiveProvider, 'premiumize');
        break;
      case DebridProviderType.allDebrid:
        KvStore.setSync(keyActiveProvider, 'alldebrid');
        break;
    }
  }

  static String buildMagnet(String infoHash, {List<String>? trackers, String? name}) {
    final hash = infoHash.trim().toLowerCase();
    final buffer = StringBuffer('magnet:?xt=urn:btih:$hash');
    if (name != null && name.isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(name)}');
    }
    if (trackers != null) {
      for (final tr in trackers) {
        if (tr.isNotEmpty) {
          buffer.write('&tr=${Uri.encodeComponent(tr)}');
        }
      }
    }
    return buffer.toString();
  }

  static Future<bool> isHashCached(String infoHash, {DebridProviderType? provider}) async {
    final targetProvider = provider ?? getActiveProvider();
    final apiKey = getApiKey(targetProvider);
    if (apiKey == null || apiKey.isEmpty) return false;

    final hash = infoHash.trim().toLowerCase();
    try {
      switch (targetProvider) {
        case DebridProviderType.realDebrid:
          final response = await _client.get(
            Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/instantAvailability/$hash'),
            headers: {'Authorization': 'Bearer $apiKey'},
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map && data.containsKey(hash)) {
              final val = data[hash];
              if (val is Map && val.containsKey('rd') && (val['rd'] as List).isNotEmpty) {
                return true;
              }
            }
          }
          return false;

        case DebridProviderType.torBox:
          final response = await _client.post(
            Uri.parse('https://api.torbox.app/v1/api/torrents/checkcached?format=object'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'hashes': [hash]
            }),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map && data['success'] == true && data['data'] is Map) {
              return (data['data'] as Map).containsKey(hash);
            }
          }
          return false;

        case DebridProviderType.premiumize:
          final response = await _client.post(
            Uri.parse('https://www.premiumize.me/api/cache/check'),
            headers: {'Authorization': 'Bearer $apiKey'},
            body: {'items[]': hash},
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map && data['status'] == 'success' && data['response'] is List) {
              final list = data['response'] as List;
              return list.isNotEmpty && list.first == true;
            }
          }
          return false;

        case DebridProviderType.allDebrid:
          final response = await _client.get(
            Uri.parse('https://api.alldebrid.com/v4/magnet/instant?agent=AnymeX&apikey=$apiKey&magnets[]=$hash'),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map && data['status'] == 'success' && data['data'] is Map) {
              final magnets = data['data']['magnets'];
              if (magnets is List && magnets.isNotEmpty) {
                return magnets.first['instant'] == true;
              }
            }
          }
          return false;
      }
    } catch (e) {
      Logger.log('isHashCached failed for $hash: $e');
      return false;
    }
  }

  static Future<DebridResolvedLink?> resolveTorrent({
    required String infoHash,
    int? fileIndex,
    int? season,
    int? episode,
    String? name,
    List<String>? trackers,
    DebridProviderType? provider,
  }) async {
    final targetProvider = provider ?? getActiveProvider();
    final apiKey = getApiKey(targetProvider);
    if (apiKey == null || apiKey.isEmpty) return null;

    final magnet = buildMagnet(infoHash, trackers: trackers, name: name);

    try {
      switch (targetProvider) {
        case DebridProviderType.realDebrid:
          return await _resolveRealDebrid(apiKey, magnet, fileIndex, season, episode);

        case DebridProviderType.torBox:
          return await _resolveTorBox(apiKey, magnet, fileIndex, season, episode);

        case DebridProviderType.premiumize:
          return await _resolvePremiumize(apiKey, magnet, fileIndex, season, episode);

        case DebridProviderType.allDebrid:
          return await _resolveAllDebrid(apiKey, magnet);
      }
    } catch (e) {
      Logger.log('resolveTorrent failed with provider $targetProvider: $e');
      return null;
    }
  }

  static Future<DebridResolvedLink?> _resolveRealDebrid(
    String apiKey,
    String magnet,
    int? fileIndex,
    int? season,
    int? episode,
  ) async {
    final addRes = await _client.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/addMagnet'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'magnet': magnet},
    );
    if (addRes.statusCode != 201 && addRes.statusCode != 200) return null;
    final addData = jsonDecode(addRes.body);
    final torrentId = addData['id']?.toString();
    if (torrentId == null) return null;

    try {
      final infoRes = await _client.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (infoRes.statusCode != 200) return null;
      final infoData = jsonDecode(infoRes.body);

      final files = (infoData['files'] as List? ?? []);
      String selectedFileId = 'all';
      if (fileIndex != null && fileIndex >= 0 && fileIndex < files.length) {
        selectedFileId = files[fileIndex]['id']?.toString() ?? 'all';
      }

      await _client.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'files': selectedFileId},
      );

      final readyInfoRes = await _client.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (readyInfoRes.statusCode != 200) return null;
      final readyData = jsonDecode(readyInfoRes.body);
      final links = readyData['links'] as List? ?? [];
      if (links.isEmpty) return null;

      final targetLink = links.first.toString();
      final unrestrictRes = await _client.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/unrestrict/link'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'link': targetLink},
      );
      if (unrestrictRes.statusCode != 200) return null;
      final unrestrictData = jsonDecode(unrestrictRes.body);
      final downloadUrl = unrestrictData['download']?.toString();
      if (downloadUrl == null) return null;

      return DebridResolvedLink(
        url: downloadUrl,
        filename: unrestrictData['filename']?.toString(),
        fileSize: unrestrictData['filesize'] is int ? unrestrictData['filesize'] : null,
        provider: 'Real-Debrid',
      );
    } catch (e) {
      try {
        await _client.delete(
          Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/delete/$torrentId'),
          headers: {'Authorization': 'Bearer $apiKey'},
        );
      } catch (_) {}
      return null;
    }
  }

  static Future<DebridResolvedLink?> _resolveTorBox(
    String apiKey,
    String magnet,
    int? fileIndex,
    int? season,
    int? episode,
  ) async {
    final createRes = await _client.post(
      Uri.parse('https://api.torbox.app/v1/api/torrents/createtorrent'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'magnet': magnet,
        'add_only_if_cached': true,
        'allow_zip': false,
      }),
    );
    if (createRes.statusCode != 200) return null;
    final createData = jsonDecode(createRes.body);
    if (createData['success'] != true || createData['data'] == null) return null;

    final torrentId = createData['data']['torrent_id'] ?? createData['data']['id'];
    if (torrentId == null) return null;

    final listRes = await _client.get(
      Uri.parse('https://api.torbox.app/v1/api/torrents/mylist?id=$torrentId&bypass_cache=true'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (listRes.statusCode != 200) return null;
    final listData = jsonDecode(listRes.body);
    final files = listData['data']?['files'] as List? ?? [];
    if (files.isEmpty) return null;

    dynamic selectedFile = files.first;
    if (fileIndex != null && fileIndex >= 0 && fileIndex < files.length) {
      selectedFile = files[fileIndex];
    } else {
      files.sort((a, b) => ((b['size'] ?? 0) as num).compareTo((a['size'] ?? 0) as num));
      selectedFile = files.first;
    }

    final fileId = selectedFile['id'];
    final dlRes = await _client.get(
      Uri.parse('https://api.torbox.app/v1/api/torrents/requestdl?token=$apiKey&torrent_id=$torrentId&file_id=$fileId&zip_link=false&redirect=false'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (dlRes.statusCode != 200) return null;
    final dlData = jsonDecode(dlRes.body);
    final downloadUrl = dlData['data']?.toString();
    if (downloadUrl == null) return null;

    return DebridResolvedLink(
      url: downloadUrl,
      filename: selectedFile['name']?.toString(),
      fileSize: selectedFile['size'] is int ? selectedFile['size'] : null,
      provider: 'TorBox',
    );
  }

  static Future<DebridResolvedLink?> _resolvePremiumize(
    String apiKey,
    String magnet,
    int? fileIndex,
    int? season,
    int? episode,
  ) async {
    final res = await _client.post(
      Uri.parse('https://www.premiumize.me/api/transfer/directdl'),
      headers: {'Authorization': 'Bearer $apiKey'},
      body: {'src': magnet},
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data['status'] != 'success') return null;

    final content = data['content'] as List? ?? [];
    if (content.isEmpty) return null;

    dynamic target = content.first;
    if (fileIndex != null && fileIndex >= 0 && fileIndex < content.length) {
      target = content[fileIndex];
    } else {
      content.sort((a, b) => ((b['size'] ?? 0) as num).compareTo((a['size'] ?? 0) as num));
      target = content.first;
    }

    final link = target['link']?.toString() ?? target['stream_link']?.toString();
    if (link == null) return null;

    return DebridResolvedLink(
      url: link,
      filename: target['path']?.toString(),
      fileSize: target['size'] is int ? target['size'] : null,
      provider: 'Premiumize',
    );
  }

  static Future<DebridResolvedLink?> _resolveAllDebrid(
    String apiKey,
    String magnet,
  ) async {
    final res = await _client.post(
      Uri.parse('https://api.alldebrid.com/v4/link/unlock?agent=AnymeX&apikey=$apiKey'),
      body: {'link': magnet},
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data['status'] != 'success' || data['data'] == null) return null;

    final link = data['data']['link']?.toString();
    if (link == null) return null;

    return DebridResolvedLink(
      url: link,
      filename: data['data']['filename']?.toString(),
      fileSize: data['data']['filesize'] is int ? data['data']['filesize'] : null,
      provider: 'AllDebrid',
    );
  }
}
