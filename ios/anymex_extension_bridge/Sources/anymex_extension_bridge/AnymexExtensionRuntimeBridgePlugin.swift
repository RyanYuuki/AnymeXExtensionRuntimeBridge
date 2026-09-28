import Flutter
import UIKit

/// iOS entry point for dartotsu_extension_bridge.
///
/// Only the embedded-JVM channel is implemented here; the plugin's other
/// channels are Android/desktop-only. The embedded VM boots lazily on the
/// first `start`/`load` and stays up for the process lifetime; it is only
/// paused/resumed with the app lifecycle.
public final class AnymexExtensionRuntimeBridgePlugin: NSObject, FlutterPlugin {
  private var vmRequested = false
  private let torrServerBridge = TorrServerBridge()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "anymex_extension_bridge/embedded_jvm",
      binaryMessenger: registrar.messenger())
    let instance = AnymexExtensionRuntimeBridgePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.observeApplicationLifecycle()
    instance.torrServerBridge.attach(to: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      vmRequested = true
      EmbeddedJvmStart { error in
        Self.finish(result, error: error, ok: nil)
      }

    case "load":
      guard let jarPath = Self.stringArg(call, "jarPath") else {
        result(Self.invalidArgs("jarPath"))
        return
      }
      vmRequested = true
      EmbeddedJvmLoad(jarPath) { error in
        Self.finish(result, error: error, ok: nil)
      }

    case "call":
      guard
        let jarPath = Self.stringArg(call, "jarPath"),
        let request = Self.stringArg(call, "request")
      else {
        result(Self.invalidArgs("jarPath/request"))
        return
      }
      EmbeddedJvmCall(jarPath, request) { response, error in
        if let error {
          result(Self.flutterError("CALL_ERROR", error))
        } else {
          result(response)
        }
      }

    case "unload":
      guard let jarPath = Self.stringArg(call, "jarPath") else {
        result(Self.invalidArgs("jarPath"))
        return
      }
      EmbeddedJvmUnload(jarPath) { error in
        Self.finish(result, error: error, ok: nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Lifecycle

  private func observeApplicationLifecycle() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  @objc private func applicationDidEnterBackground() {
    guard vmRequested else { return }
    EmbeddedJvmPause { _ in }
  }

  @objc private func applicationDidBecomeActive() {
    guard vmRequested else { return }
    EmbeddedJvmResume { _ in }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Helpers

  private static func stringArg(_ call: FlutterMethodCall, _ key: String) -> String? {
    (call.arguments as? [String: Any])?[key] as? String
  }

  private static func invalidArgs(_ what: String) -> FlutterError {
    FlutterError(code: "INVALID_ARGS", message: "Missing '\(what)'", details: nil)
  }

  private static func flutterError(_ code: String, _ error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }

  private static func finish(
    _ result: @escaping FlutterResult, error: Error?, ok: Any?
  ) {
    if let error {
      result(flutterError("EMBEDDED_JVM_ERROR", error))
    } else {
      result(ok)
    }
  }
}
