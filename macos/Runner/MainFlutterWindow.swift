import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var folderChannel: FolderChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Phone-first UI: open tall and narrow, and never smaller than a small phone.
    self.minSize = NSSize(width: 360, height: 560)
    self.setContentSize(NSSize(width: 460, height: 860))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FolderChannel(messenger: flutterViewController.engine.binaryMessenger)
    folderChannel = channel
    DispatchQueue.main.async { channel.installMenu() }

    super.awakeFromNib()
  }
}
