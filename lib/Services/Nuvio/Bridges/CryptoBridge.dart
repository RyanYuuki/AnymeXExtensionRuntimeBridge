import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

class CryptoBridge {
  static final Random _secureRandom = Random.secure();

  static Uint8List hexToBytes(String hex) {
    var cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length % 2 != 0) {
      cleaned = '0$cleaned';
    }
    final bytes = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < cleaned.length; i += 2) {
      bytes[i ~/ 2] = int.parse(cleaned.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  static String digest(String algorithm, String hexData) {
    final bytes = hexToBytes(hexData);
    final algo = algorithm.toUpperCase().replaceAll('-', '');

    List<int> hashBytes;
    switch (algo) {
      case 'MD5':
        hashBytes = crypto.md5.convert(bytes).bytes;
        break;
      case 'SHA1':
        hashBytes = crypto.sha1.convert(bytes).bytes;
        break;
      case 'SHA256':
        hashBytes = crypto.sha256.convert(bytes).bytes;
        break;
      case 'SHA384':
        hashBytes = crypto.sha384.convert(bytes).bytes;
        break;
      case 'SHA512':
        hashBytes = crypto.sha512.convert(bytes).bytes;
        break;
      default:
        hashBytes = crypto.sha256.convert(bytes).bytes;
    }
    return bytesToHex(hashBytes);
  }

  static String hmac(String algorithm, String hexKey, String hexData) {
    final key = hexToBytes(hexKey);
    final data = hexToBytes(hexData);
    final algo = algorithm.toUpperCase().replaceAll('-', '');

    crypto.Hash hash;
    switch (algo) {
      case 'MD5':
        hash = crypto.md5;
        break;
      case 'SHA1':
        hash = crypto.sha1;
        break;
      case 'SHA256':
        hash = crypto.sha256;
        break;
      case 'SHA384':
        hash = crypto.sha384;
        break;
      case 'SHA512':
        hash = crypto.sha512;
        break;
      default:
        hash = crypto.sha256;
    }

    final hmacEngine = crypto.Hmac(hash, key);
    final result = hmacEngine.convert(data);
    return bytesToHex(result.bytes);
  }

  static String aesEncrypt(String modeName, String hexKey, String hexIv, String hexData) {
    final keyBytes = hexToBytes(hexKey);
    final ivBytes = hexToBytes(hexIv);
    final dataBytes = hexToBytes(hexData);

    final key = enc.Key(keyBytes);
    final iv = enc.IV(ivBytes.isNotEmpty ? ivBytes : Uint8List(16));

    final normalizedMode = modeName.toUpperCase();

    enc.Encrypter encrypter;
    if (normalizedMode.contains('GCM')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    } else if (normalizedMode.contains('CTR') || normalizedMode.contains('SIC')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ctr, padding: null));
    } else if (normalizedMode.contains('ECB')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    } else {
      final padding = normalizedMode.contains('NOPADDING') ? null : 'PKCS7';
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: padding));
    }

    final encrypted = encrypter.encryptBytes(dataBytes, iv: iv);
    return bytesToHex(encrypted.bytes);
  }

  static String aesDecrypt(String modeName, String hexKey, String hexIv, String hexData) {
    final keyBytes = hexToBytes(hexKey);
    final ivBytes = hexToBytes(hexIv);
    final dataBytes = hexToBytes(hexData);

    final key = enc.Key(keyBytes);
    final iv = enc.IV(ivBytes.isNotEmpty ? ivBytes : Uint8List(16));

    final normalizedMode = modeName.toUpperCase();

    enc.Encrypter encrypter;
    if (normalizedMode.contains('GCM')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    } else if (normalizedMode.contains('CTR') || normalizedMode.contains('SIC')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ctr, padding: null));
    } else if (normalizedMode.contains('ECB')) {
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    } else {
      final padding = normalizedMode.contains('NOPADDING') ? null : 'PKCS7';
      encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: padding));
    }

    final decrypted = encrypter.decryptBytes(enc.Encrypted(dataBytes), iv: iv);
    return bytesToHex(decrypted);
  }

  static String pbkdf2(
    String hexPassword,
    String hexSalt,
    int iterations,
    int keySizeBits,
    String hashName,
  ) {
    final password = hexToBytes(hexPassword);
    final salt = hexToBytes(hexSalt);
    final algo = hashName.toUpperCase().replaceAll('-', '');

    crypto.Hash hash;
    switch (algo) {
      case 'MD5':
        hash = crypto.md5;
        break;
      case 'SHA1':
        hash = crypto.sha1;
        break;
      case 'SHA256':
        hash = crypto.sha256;
        break;
      case 'SHA384':
        hash = crypto.sha384;
        break;
      case 'SHA512':
        hash = crypto.sha512;
        break;
      default:
        hash = crypto.sha1;
    }

    final targetSizeBytes = keySizeBits ~/ 8;
    final hLen = hash.convert(Uint8List(0)).bytes.length;
    final l = (targetSizeBytes + hLen - 1) ~/ hLen;
    final out = Uint8List(targetSizeBytes);

    var outOffset = 0;
    for (var i = 1; i <= l; i++) {
      final blockIndexBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, i, Endian.big);

      final saltAndIndex = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..setRange(salt.length, salt.length + 4, blockIndexBytes);

      var u = crypto.Hmac(hash, password).convert(saltAndIndex).bytes;
      final t = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = crypto.Hmac(hash, password).convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }

      final copyLen = min(hLen, targetSizeBytes - outOffset);
      out.setRange(outOffset, outOffset + copyLen, t.sublist(0, copyLen));
      outOffset += copyLen;
    }

    return bytesToHex(out);
  }

  static String getRandomValues(int byteLength) {
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytesToHex(bytes);
  }

  static String utf8ToHex(String str) {
    return bytesToHex(utf8.encode(str));
  }

  static String hexToUtf8(String hex) {
    try {
      return utf8.decode(hexToBytes(hex));
    } catch (_) {
      return '';
    }
  }
}
