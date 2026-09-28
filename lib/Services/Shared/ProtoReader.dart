import 'dart:convert';
import 'dart:typed_data';

class ProtoMessage {
  final Map<int, List<Object>> fields;

  const ProtoMessage(this.fields);

  static ProtoMessage decode(Uint8List bytes) {
    final fields = <int, List<Object>>{};
    var i = 0;

    while (i < bytes.length) {
      final (key, afterKey) = _varint(bytes, i);
      i = afterKey;

      final field = key >> 3;
      final wireType = key & 0x7;

      Object value;
      switch (wireType) {
        case 0:
          final (v, next) = _varint(bytes, i);
          i = next;
          value = v;
          break;
        case 1:
          if (i + 8 > bytes.length) return ProtoMessage(fields);
          value = bytes.buffer
              .asByteData(bytes.offsetInBytes + i, 8)
              .getUint64(0, Endian.little);
          i += 8;
          break;
        case 2:
          final (len, next) = _varint(bytes, i);
          i = next;
          if (i + len > bytes.length) return ProtoMessage(fields);
          value = Uint8List.sublistView(bytes, i, i + len);
          i += len;
          break;
        case 5:
          if (i + 4 > bytes.length) return ProtoMessage(fields);
          value = bytes.buffer
              .asByteData(bytes.offsetInBytes + i, 4)
              .getUint32(0, Endian.little);
          i += 4;
          break;
        default:
          return ProtoMessage(fields);
      }

      (fields[field] ??= <Object>[]).add(value);
    }

    return ProtoMessage(fields);
  }

  static (int, int) _varint(Uint8List bytes, int start) {
    var result = 0;
    var shift = 0;
    var i = start;

    while (i < bytes.length) {
      final b = bytes[i++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
      if (shift > 63) break;
    }

    return (result, i);
  }

  bool has(int field) => fields.containsKey(field);

  Object? _last(int field) {
    final values = fields[field];
    return (values == null || values.isEmpty) ? null : values.last;
  }

  int? readInt(int field) {
    final v = _last(field);
    return v is int ? v : null;
  }

  String? readString(int field) {
    final v = _last(field);
    if (v is! Uint8List) return null;
    try {
      return utf8.decode(v, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  ProtoMessage? readMessage(int field) {
    final v = _last(field);
    return v is Uint8List ? ProtoMessage.decode(v) : null;
  }

  List<ProtoMessage> readMessages(int field) => [
    for (final v in fields[field] ?? const <Object>[])
      if (v is Uint8List) ProtoMessage.decode(v),
  ];

  List<String> readStrings(int field) => [
    for (final v in fields[field] ?? const <Object>[])
      if (v is Uint8List) utf8.decode(v, allowMalformed: true),
  ];
}
