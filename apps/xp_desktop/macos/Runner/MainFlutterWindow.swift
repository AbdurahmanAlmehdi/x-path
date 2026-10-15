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

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacosServicesChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
