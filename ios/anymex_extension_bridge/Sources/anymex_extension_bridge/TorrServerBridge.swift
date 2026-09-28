import Flutter
import TorrServerKit

/// Drives the embedded, statically-linked TorrServer engine
/// (`TorrServerKit.xcframework`, a `gomobile bind` build of
/// github.com/ayman708-UX/torrserver_flutter) over the
/// `anymex_extension_bridge/torrserver` channel that `TorrServerControllerIos`
/// (Dart side) calls into. Only `start`/`stop`/`isRunning` are handled here -
/// once started, everything else (addTorrent, listTorrents, ...) talks to the
/// engine directly over its own loopback HTTP REST API from Dart.
final class TorrServerBridge: NSObject {
  private var channel: FlutterMethodChannel?

  func attach(to registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "anymex_extension_bridge/torrserver",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler(handle)
    self.channel = channel
  }

  func detach() {
    channel?.setMethodCallHandler(nil)
    channel = nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startServer":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a dictionary", details: nil))
        return
      }
      let port = args["port"] as? Int ?? 8090
      let dataDir = args["dataDir"] as? String ?? ""

      DispatchQueue.global(qos: .userInitiated).async {
        let errStr = TorrserverkitStartServer(port, dataDir)
        DispatchQueue.main.async {
          if !errStr.isEmpty {
            result(FlutterError(code: "START_FAILED", message: errStr, details: nil))
          } else {
            result(nil)
          }
        }
      }

    case "stopServer":
      DispatchQueue.global(qos: .userInitiated).async {
        let errStr = TorrserverkitStopServer()
        DispatchQueue.main.async {
          if !errStr.isEmpty {
            result(FlutterError(code: "STOP_FAILED", message: errStr, details: nil))
          } else {
            result(nil)
          }
        }
      }

    case "isRunning":
      result(TorrserverkitIsRunning())

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
