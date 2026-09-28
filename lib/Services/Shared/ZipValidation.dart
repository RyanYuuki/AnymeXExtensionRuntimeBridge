import 'dart:io';

Future<bool> hasZipSignature(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final header = await raf.read(4);
    if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4B) {
      return false;
    }
    return (header[2] == 0x03 && header[3] == 0x04) ||
        (header[2] == 0x05 && header[3] == 0x06) ||
        (header[2] == 0x07 && header[3] == 0x08);
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}
