import Cocoa
import FlutterMacOS

/// Lets the user pick the folder their screenshots are saved to, and keeps
/// access to it across launches with a security-scoped bookmark. The app
/// sandbox stays on: macOS grants access to exactly the folder the user
/// chose in the open panel, and the bookmark carries that grant forward.
///
/// Channel `app.fluo/folder`:
///  - `pick`            -> {path, bookmark} or nil when cancelled
///  - `open(bookmark)`  -> {path, stale, bookmark?} (a fresh bookmark when the
///                         old one was stale); a FlutterError when it cannot
///                         be resolved or access is refused
///  - `close`           -> stops the current security-scoped access
final class FolderChannel {
  private var scoped: URL?

  init(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.fluo/folder", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result)
    case "open":
      guard let b64 = call.arguments as? String else {
        return result(FlutterError(code: "args", message: "bookmark missing", details: nil))
      }
      open(b64, result)
    case "close":
      release()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func release() {
    scoped?.stopAccessingSecurityScopedResource()
    scoped = nil
  }

  private func pick(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Watch this folder"
    panel.message = "Choose the folder your screenshots are saved to."
    panel.begin { [weak self] response in
      guard let self = self, response == .OK, let url = panel.url else { return result(nil) }
      do {
        let data = try url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        self.release()
        guard url.startAccessingSecurityScopedResource() else {
          return result(FlutterError(code: "access", message: "access refused", details: nil))
        }
        self.scoped = url
        result(["path": url.path, "bookmark": data.base64EncodedString()])
      } catch {
        result(FlutterError(code: "bookmark", message: "\(error)", details: nil))
      }
    }
  }

  private func open(_ b64: String, _ result: @escaping FlutterResult) {
    guard let data = Data(base64Encoded: b64) else {
      return result(FlutterError(code: "bookmark", message: "bad bookmark", details: nil))
    }
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &stale)
      release()
      guard url.startAccessingSecurityScopedResource() else {
        return result(FlutterError(code: "access", message: "access refused", details: nil))
      }
      scoped = url
      var out: [String: Any] = ["path": url.path, "stale": stale]
      if stale,
        let fresh = try? url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      {
        out["bookmark"] = fresh.base64EncodedString()
      }
      result(out)
    } catch {
      result(FlutterError(code: "bookmark", message: "\(error)", details: nil))
    }
  }
}
