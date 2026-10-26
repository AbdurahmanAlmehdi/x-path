import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Whether closing the window keeps XPath running in the menu bar (UX-07),
  /// as the Dart side sets it in Settings; on by default.
  static let keepRunningKey = "keepRunningInMenuBar"

  override func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.register(defaults: [Self.keepRunningKey: true])
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !UserDefaults.standard.bool(forKey: Self.keepRunningKey)
  }

  /// A click on the Dock icon with the window closed shows it again.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { Self.showMainWindow() }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Brings the main window forward, also after it was closed.
  static func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(nil)
  }

  /// XPath ▸ Settings… (⌘,): the Dart side shows the settings page.
  @IBAction func openSettings(_ sender: Any?) {
    MacosServicesChannel.openSettings()
  }
}
