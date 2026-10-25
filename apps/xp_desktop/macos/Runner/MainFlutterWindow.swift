import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // The Run Sheet minimum (`window.min.*`, 1100 x 700).
    self.minSize = NSSize(width: 1100, height: 700)
    // Closing hides the window; XPath keeps running in the menu bar (UX-07),
    // and the Dock icon or "Open XPath" shows it again.
    self.isReleasedWhenClosed = false
    // macOS keeps the frame and restores it at the next launch (U6b).
    self.setFrameAutosaveName("XPathMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacosServicesChannel.register(with: flutterViewController.engine.binaryMessenger)
    NeedsYouChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
