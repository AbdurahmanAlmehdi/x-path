import Cocoa
import FlutterMacOS
import Security
import ServiceManagement
import UserNotifications

/// The macOS side of `packages/xp_macos_services`: the LaunchAgent of the
/// bundled engine (SMAppService) and the app's own Keychain items.
/// Identifiers follow ADR 0005.
enum MacosServicesChannel {
  static let name = "ly.abdurahman.xpath/macos_services"

  /// `Contents/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`.
  static let agentPlist = "ly.abdurahman.xpath.xpd.plist"

  /// The Keychain service of the app's items (engine tokens).
  static let keychainService = "ly.abdurahman.xpath.app"

  /// The prefix of every Keychain service of XPath (ADR 0005).
  static let keychainPrefix = "ly.abdurahman.xpath"

  /// The app menu: XPath ▸ Settings… goes to Dart through it.
  static let appMenuName = "ly.abdurahman.xpath/app_menu"

  private static var appMenu: FlutterMethodChannel?

  /// Asks the Dart side to show the settings page.
  static func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    appMenu?.invokeMethod("settings", arguments: nil)
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    appMenu = FlutterMethodChannel(name: appMenuName, binaryMessenger: messenger)
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "agentStatus":
        result(agentStatus())
      case "agentRegister":
        registerAgent(result)
      case "agentUnregister":
        unregisterAgent(result)
      case "keychainItems":
        keychainItems(arguments["prefix"] as? String ?? keychainPrefix, result)
      case "appVersion":
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        result("\(short) (\(build))")
      case "appMoveToTrash":
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
          DispatchQueue.main.async { result(error == nil) }
        }
      case "appQuit":
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
      case "openLoginItems":
        if #available(macOS 13.0, *) {
          SMAppService.openSystemSettingsLoginItems()
        }
        result(nil)
      case "keychainRead":
        keychainRead(arguments["account"] as? String ?? "", result)
      case "keychainWrite":
        keychainWrite(
          arguments["account"] as? String ?? "",
          arguments["value"] as? String ?? "",
          result
        )
      case "keychainDelete":
        keychainDelete(arguments["account"] as? String ?? "", result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: LaunchAgent

  private static func agentStatus() -> String {
    guard #available(macOS 13.0, *) else { return "unsupported" }
    return describe(SMAppService.agent(plistName: agentPlist).status)
  }

  @available(macOS 13.0, *)
  private static func describe(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "notFound"
    }
  }

  private static func registerAgent(_ result: FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result("unsupported")
      return
    }
    let service = SMAppService.agent(plistName: agentPlist)
    do {
      try service.register()
      result(describe(service.status))
    } catch {
      let code = (error as NSError).code
      if service.status == .requiresApproval || code == kSMErrorLaunchDeniedByUser {
        // Registered, but the user has to allow it in Login Items first.
        result("requiresApproval")
      } else if code == kSMErrorJobPlistNotFound || code == kSMErrorInvalidPlist {
        // A build without the engine (it is copied in by Phase 18b).
        result("notFound")
      } else if code == kSMErrorAlreadyRegistered {
        result(describe(service.status))
      } else {
        result(
          FlutterError(
            code: "register_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private static func unregisterAgent(_ result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result("unsupported")
      return
    }
    let service = SMAppService.agent(plistName: agentPlist)
    // Unregistering waits until launchd has stopped the engine.
    service.unregister { error in
      DispatchQueue.main.async {
        let code = (error as NSError?)?.code
        if error == nil || code == kSMErrorJobNotFound {
          result(describe(service.status))
        } else {
          result(
            FlutterError(
              code: "unregister_failed",
              message: error?.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  // MARK: Keychain

  /// The service and account of every generic password whose service is
  /// [prefix] or under it. Only the names: no value is read, so macOS asks
  /// for nothing.
  private static func keychainItems(_ prefix: String, _ result: FlutterResult) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: true,
    ]
    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    switch status {
    case errSecSuccess:
      let all = items as? [[String: Any]] ?? []
      result(
        all.compactMap { item -> [String: String]? in
          guard
            let service = item[kSecAttrService as String] as? String,
            service == prefix || service.hasPrefix(prefix + "."),
            let account = item[kSecAttrAccount as String] as? String
          else { return nil }
          return ["service": service, "account": account]
        }
      )
    case errSecItemNotFound:
      result([])
    default:
      result(failure(status))
    }
  }

  private static func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
    ]
  }

  private static func failure(_ status: OSStatus) -> FlutterError {
    let locked = status == errSecInteractionNotAllowed
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    return FlutterError(code: locked ? "locked" : "keychain", message: message, details: nil)
  }

  private static func keychainRead(_ account: String, _ result: FlutterResult) {
    var item = query(account)
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var data: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &data)
    switch status {
    case errSecSuccess:
      result((data as? Data).flatMap { String(data: $0, encoding: .utf8) })
    case errSecItemNotFound:
      result(nil)
    default:
      result(failure(status))
    }
  }

  private static func keychainWrite(_ account: String, _ value: String, _ result: FlutterResult) {
    let data = Data(value.utf8)
    var status = SecItemUpdate(
      query(account) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      var item = query(account)
      item[kSecValueData as String] = data
      item[kSecAttrLabel as String] = "XPath engine token"
      status = SecItemAdd(item as CFDictionary, nil)
    }
    result(status == errSecSuccess ? nil : failure(status))
  }

  private static func keychainDelete(_ account: String, _ result: FlutterResult) {
    let status = SecItemDelete(query(account) as CFDictionary)
    result(status == errSecSuccess || status == errSecItemNotFound ? nil : failure(status))
  }
}

/// The macOS side of `NeedsYouAlerts` in `packages/xp_macos_services`: the
/// notifications of approvals that wait and the menu bar extra (a status
/// item with the `XPathTemplate` image and a native menu). Neither decides
/// anything: their buttons call back into Dart, which opens the
/// confirmation sheet in the main window (DECISIONS.md).
final class NeedsYouChannel: NSObject, UNUserNotificationCenterDelegate {
  static let name = "ly.abdurahman.xpath/needs_you"

  /// The notification category with the "Review…" and "Later" buttons.
  static let category = "ly.abdurahman.xpath.approval"

  static let shared = NeedsYouChannel()

  private var channel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    shared.channel = channel
    // Setting the delegate asks for nothing; it routes the clicks on
    // notifications, also those that launched the app.
    UNUserNotificationCenter.current().delegate = shared
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "notify":
        shared.notify(arguments)
        result(nil)
      case "withdraw":
        let id = arguments["id"] as? String ?? ""
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
        result(nil)
      case "menuBar":
        shared.updateMenuBar(arguments)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Notifications

  private func notify(_ arguments: [String: Any]) {
    let id = arguments["id"] as? String ?? ""
    let center = UNUserNotificationCenter.current()
    let review = UNNotificationAction(
      identifier: "review",
      title: arguments["review"] as? String ?? "Review…",
      options: [.foreground]
    )
    let later = UNNotificationAction(
      identifier: "later",
      title: arguments["later"] as? String ?? "Later",
      options: []
    )
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.category,
        actions: [review, later],
        intentIdentifiers: [],
        options: []
      )
    ])
    // macOS asks the owner once; afterwards this answers at once.
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = arguments["title"] as? String ?? ""
      content.body = arguments["body"] as? String ?? ""
      content.categoryIdentifier = Self.category
      content.sound = .default
      center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let id = response.notification.request.identifier
    switch response.actionIdentifier {
    case "review":
      send("review", id)
    case UNNotificationDefaultActionIdentifier:
      send("show", id)
    default:
      // "Later" or dismissed: nothing to do.
      break
    }
    completionHandler()
  }

  // MARK: Menu bar extra

  private func updateMenuBar(_ arguments: [String: Any]) {
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    if let button = item.button {
      let image = NSImage(named: "XPathTemplate")
      image?.isTemplate = true
      button.image = image
      button.imagePosition = .imageLeft
      button.toolTip = arguments["tooltip"] as? String
      let needsYou = arguments["needsYou"] as? Bool ?? false
      button.attributedTitle = NSAttributedString(
        string: needsYou ? " ●" : "",
        attributes: [.font: NSFont.systemFont(ofSize: 8)]
      )
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    let header = NSMenuItem(title: arguments["header"] as? String ?? "", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    for entry in arguments["items"] as? [[String: Any]] ?? [] {
      let row = NSMenuItem(
        title: entry["title"] as? String ?? "",
        action: #selector(review(_:)),
        keyEquivalent: ""
      )
      row.target = self
      row.representedObject = entry["id"] as? String
      row.toolTip = entry["detail"] as? String
      if #available(macOS 14.4, *) {
        row.subtitle = entry["detail"] as? String
      }
      menu.addItem(row)
    }
    menu.addItem(.separator())
    let open = NSMenuItem(
      title: arguments["openApp"] as? String ?? "",
      action: #selector(openApp),
      keyEquivalent: ""
    )
    open.target = self
    menu.addItem(open)
    item.menu = menu
  }

  @objc private func review(_ sender: NSMenuItem) {
    send("review", sender.representedObject as? String)
  }

  @objc private func openApp() {
    send("open", nil)
  }

  /// Brings the main window forward, then tells Dart what was clicked.
  private func send(_ method: String, _ id: String?) {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(nil)
      self.channel?.invokeMethod(method, arguments: id.map { ["id": $0] })
    }
  }
}
