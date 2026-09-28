import 'dart:io';

import 'Exceptions.dart';

/// Utility class for finding free, available TCP ports on the local machine.
class PortFinder {
  /// Finds an available TCP port by binding a throwaway server socket on loopback
  /// and immediately releasing it.
  ///
  /// Throws [TorrServerPortException] if socket binding fails.
  static Future<int> findFreePort() async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      final port = socket.port;
      await socket.close();
      return port;
    } catch (e) {
      if (socket != null) {
        try {
          await socket.close();
        } catch (_) {}
      }
      throw TorrServerPortException(
        'Failed to find an available local TCP port for TorrServer',
        null,
        e,
      );
    }
  }

  /// Checks whether a specific port is currently available on the loopback address.
  static Future<bool> isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      await socket.close();
      return true;
    } catch (_) {
      if (socket != null) {
        try {
          await socket.close();
        } catch (_) {}
      }
      return false;
    }
  }
}
