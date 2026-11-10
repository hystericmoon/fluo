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
final class FolderChannel: NSObject {
  private var scoped: URL?
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.fluo/folder", binaryMessenger: messenger)
    super.init()
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

  /// A "Capture" menu next to Window: the same two actions as the session
  /// card, for people who live in the menu bar. Dart does the work.
  func installMenu() {
    guard let main = NSApp.mainMenu else { return }
    let menu = NSMenu(title: "Capture")
    let choose = NSMenuItem(
      title: "Choose Screenshot Folder…", action: #selector(menuChoose), keyEquivalent: "o")
    choose.keyEquivalentModifierMask = [.command, .shift]
    choose.target = self
    let reset = NSMenuItem(
      title: "Use Default Screenshot Folder", action: #selector(menuReset), keyEquivalent: "")
    reset.target = self
    menu.addItem(choose)
    menu.addItem(reset)
    let item = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
    item.submenu = menu
    // Before Window and Help, after Edit and View.
    main.insertItem(item, at: max(1, main.items.count - 2))
  }

  @objc private func menuChoose() { channel.invokeMethod("menu", arguments: "chooseFolder") }
  @objc private func menuReset() { channel.invokeMethod("menu", arguments: "useDefaultFolder") }

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
