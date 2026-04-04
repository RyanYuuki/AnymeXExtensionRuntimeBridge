import 'dart:io';
import 'JniBridge.dart';
import 'SidecarBridge.dart';

enum BridgeType { jni, sidecar }

class BridgeDispatcher {
  static final BridgeDispatcher _instance = BridgeDispatcher._internal();
  factory BridgeDispatcher() => _instance;
  BridgeDispatcher._internal();

  BridgeType _mode = Platform.isMacOS ? BridgeType.sidecar : BridgeType.jni;

  void setMode(BridgeType mode) {
    _mode = mode;
    print('Bridge Mode set to: $_mode');
  }

  BridgeType get mode => _mode;

  Future<void> initialize(String bridgeJarPath) async {
    if (_mode == BridgeType.jni) {
      await JniBridge().initialize(bridgeJarPath);
    } else {
      await SidecarBridge().initialize(bridgeJarPath);
    }
  }

  Future<dynamic> invokeMethod(String method, Map<String, dynamic> args) async {
    if (_mode == BridgeType.jni) {
      return await JniBridge().invokeMethod(method, args);
    } else {
      return await SidecarBridge().invokeMethod(method, args);
    }
  }

  Future<bool> cancelRequest(String id) async {
    if (_mode == BridgeType.jni) {
      return JniBridge().cancelRequest(id);
    } else {
      return SidecarBridge().cancelRequest(id);
    }
  }

  void dispose() {
    if (_mode == BridgeType.jni) {
      JniBridge().dispose();
    } else {
      SidecarBridge().dispose();
    }
  }
}
