import Cocoa
import FlutterMacOS
import Security
import ServiceManagement

/// The macOS side of `packages/xp_macos_services`: the LaunchAgent of the
/// bundled engine (SMAppService) and the app's own Keychain items.
/// Identifiers follow ADR 0005.
enum MacosServicesChannel {
  static let name = "ly.abdurahman.xpath/macos_services"

  /// `Contents/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`.
  static let agentPlist = "ly.abdurahman.xpath.xpd.plist"

  /// The Keychain service of the app's items (engine tokens).
  static let keychainService = "ly.abdurahman.xpath.app"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "agentStatus":
        result(agentStatus())
      case "agentRegister":
        registerAgent(result)
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

  // MARK: Keychain

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
