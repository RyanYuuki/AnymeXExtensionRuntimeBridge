import 'dart:convert';

class PbDecoder {
  static List<Map<String, dynamic>> decodeIndex(List<int> bytes) {
    final rootMap = _parseMessage(bytes, 0, bytes.length);

    final extListBytes = rootMap[101]?.first as List<int>?;
    if (extListBytes != null) {
      final extListMap = _parseMessage(extListBytes, 0, extListBytes.length);

      final extensions = extListMap[1] ?? [];
      return _parseExtensions(extensions);
    }

    final extensions = rootMap[1];
    if (extensions != null &&
        extensions.isNotEmpty &&
        extensions.first is List<int>) {
      final firstExtMap = _parseMessage(extensions.first as List<int>, 0,
          (extensions.first as List<int>).length);
      if (firstExtMap.containsKey(2)) {
        return _parseExtensions(extensions);
      }
    }

    return const [];
  }

  static List<Map<String, dynamic>> _parseExtensions(
      List<dynamic> extensionList) {
    final results = <Map<String, dynamic>>[];
    for (final extObj in extensionList) {
      final extBytes = extObj as List<int>;
      final extMap = _parseMessage(extBytes, 0, extBytes.length);

      final name = _getString(extMap[1]);
      final packageName = _getString(extMap[2]);

      final resBytes = extMap[3]?.first as List<int>?;
      String apkUrl = '';
      if (resBytes != null) {
        final resMap = _parseMessage(resBytes, 0, resBytes.length);
        apkUrl = _getString(resMap[1]);
      }

      final versionCode = _getInt(extMap[5]);
      final versionName = _getString(extMap[6]);
      final contentWarning = _getInt(extMap[7]);

      final sourcesList = <Map<String, dynamic>>[];
      final sources = extMap[8] ?? [];
      for (final srcObj in sources) {
        final srcBytes = srcObj as List<int>;
        final srcMap = _parseMessage(srcBytes, 0, srcBytes.length);
        final id = _getInt(srcMap[1]);
        final srcName = _getString(srcMap[2]);
        final lang = _getString(srcMap[3]);
        final homeUrl = _getString(srcMap[4]);

        sourcesList.add({
          'id': id,
          'name': srcName,
          'lang': lang,
          'baseUrl': homeUrl,
        });
      }

      results.add({
        'name': name,
        'pkg': packageName,
        'apk': apkUrl.contains('/') ? apkUrl.split('/').last : apkUrl,
        'lang': sourcesList.isNotEmpty ? sourcesList.first['lang'] : 'en',
        'code': versionCode,
        'version': versionName,
        'isNsfw': contentWarning >= 2,
        'sources': sourcesList,
      });
    }
    return results;
  }

  static Map<int, List<dynamic>> _parseMessage(
      List<int> bytes, int start, int end) {
    final map = <int, List<dynamic>>{};
    int pos = start;
    final outLen = [0];
    try {
      while (pos < end) {
        final key = _readVarint(bytes, pos, outLen);
        pos += outLen[0];
        final wireType = key & 0x7;
        final fieldNum = key >> 3;

        if (wireType == 0) {
          final val = _readVarint(bytes, pos, outLen);
          pos += outLen[0];
          map.putIfAbsent(fieldNum, () => []).add(val);
        } else if (wireType == 1) {
          pos += 8;
        } else if (wireType == 2) {
          final len = _readVarint(bytes, pos, outLen);
          pos += outLen[0];
          final val = bytes.sublist(pos, pos + len);
          pos += len;
          map.putIfAbsent(fieldNum, () => []).add(val);
        } else if (wireType == 5) {
          pos += 4;
        } else {
          break;
        }
      }
    } catch (_) {}
    return map;
  }

  static int _readVarint(List<int> bytes, int offset, List<int> outLen) {
    int result = 0;
    int shift = 0;
    int pos = offset;
    while (pos < bytes.length) {
      int b = bytes[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) {
        outLen[0] = pos - offset;
        return result;
      }
      shift += 7;
    }
    outLen[0] = pos - offset;
    return result;
  }

  static String _getString(List<dynamic>? list) {
    if (list == null || list.isEmpty) return '';
    try {
      return utf8.decode(list.first as List<int>);
    } catch (_) {
      return '';
    }
  }

  static int _getInt(List<dynamic>? list) {
    if (list == null || list.isEmpty) return 0;
    return list.first as int;
  }
}
