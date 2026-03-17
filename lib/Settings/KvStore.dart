import 'dart:convert';

import 'package:isar_community/isar.dart';

import '../Logger.dart';
import '../anymex_extension_runtime_bridge.dart';

part 'KvStore.g.dart';

@collection
class KvEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String key;

  late String value;
}

class KvStore {
  static final Isar _isar = AnymeXExtensionBridge.context.isar;

  static void setSync(String key, dynamic value) {
    _isar.writeTxnSync(() {
      final existing = _isar.kvEntrys.filter().keyEqualTo(key).findFirstSync();

      final entry = existing ?? KvEntry();
      entry.key = key;
      entry.value = _encode(value);

      _isar.kvEntrys.putSync(entry);
    });
  }

  static T? get<T>(String key) {
    final entry = _isar.kvEntrys.filter().keyEqualTo(key).findFirstSync();

    if (entry == null) return null;

    final decoded = _decode(entry.value);

    // Direct match
    if (decoded is T) return decoded;

    // Handle List<T>
    if (decoded is List) {
      if (T.toString() == 'List<String>') {
        return List<String>.from(decoded) as T;
      }
      if (T.toString() == 'List<int>') {
        return List<int>.from(decoded) as T;
      }
      if (T.toString() == 'List<double>') {
        return List<double>.from(decoded) as T;
      }
      if (T.toString() == 'List<bool>') {
        return List<bool>.from(decoded) as T;
      }
    }

    throw StateError(
      'Stored value for key "$key" is not of expected type $T '
      '(actual: ${decoded.runtimeType})',
    );
  }

  static Future<void> remove(String key) async {
    await _isar.writeTxn(() async {
      await _isar.kvEntrys.filter().keyEqualTo(key).deleteAll();
    });
  }

  static String _encode(dynamic value) => jsonEncode(_wrap(value));

  static dynamic _decode(String raw) {
    final data = jsonDecode(raw);
    return _unwrap(data);
  }

  static Map<String, dynamic> _wrap(dynamic value) {
    if (value == null) return {'t': 'null', 'v': null};
    if (value is String) return {'t': 'string', 'v': value};
    if (value is int) return {'t': 'int', 'v': value};
    if (value is double) return {'t': 'double', 'v': value};
    if (value is bool) return {'t': 'bool', 'v': value};

    if (value is List) {
      return {
        't': 'list',
        'v': value.map(_wrap).toList(),
      };
    }

    throw UnsupportedError(
      'KvStore only supports primitive values and List<primitive>',
    );
  }

  static dynamic _unwrap(Map<String, dynamic> data) {
    final type = data['t'];
    final value = data['v'];

    switch (type) {
      case 'null':
        return null;
      case 'string':
      case 'int':
      case 'double':
      case 'bool':
        return value;
      case 'list':
        return (value as List)
            .map((e) => _unwrap(e as Map<String, dynamic>))
            .toList();
      default:
        throw StateError('Unknown stored type: $type');
    }
  }
}

T? getVal<T>(String key, {T? defaultValue}) {
  try {
    return KvStore.get<T>(key) ?? defaultValue;
  } catch (e) {
    Logger.log('Failed to get value for key "$key": $e');
    return defaultValue;
  }
}

void setVal(String key, dynamic value) async {
  try {
    KvStore.setSync(key, value);
  } catch (e) {
    Logger.log('Failed to set value for key "$key": $e');
  }
}
