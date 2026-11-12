import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var folderChannel: FolderChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Desktop layout (sidebar, grid, inspector) from 900 wide; narrower windows
    // fall back to the phone layout, down to a small phone.
    self.minSize = NSSize(width: 360, height: 560)
    // Always open at the desktop size: a saved phone-sized frame from earlier
    // builds would hide the desktop layout.
    self.isRestorable = false
    self.setContentSize(NSSize(width: 1280, height: 820))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FolderChannel(messenger: flutterViewController.engine.binaryMessenger)
    folderChannel = channel
    DispatchQueue.main.async { channel.installMenu() }

    super.awakeFromNib()
  }
}
