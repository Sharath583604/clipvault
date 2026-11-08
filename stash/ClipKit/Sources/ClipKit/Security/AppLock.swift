import Foundation
import Observation
import LocalAuthentication

/// Seam for biometric/passcode authentication so the lock logic is testable.
public protocol Authenticating: Sendable {
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async -> Bool
}

/// Face ID / Touch ID with device passcode fallback.
public struct DeviceAuthenticator: Authenticating {
    public init() {}

    public func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Optional lock for the main app UI. It locks at launch and whenever the app goes to the
/// background. It does **not** protect the keyboard, widget or Shortcuts: those run in other
/// processes and are meant to work without opening the app.
@MainActor
@Observable
public final class AppLock {
    public private(set) var isLocked: Bool
    public private(set) var isEnabled: Bool
    public private(set) var isAuthenticating = false

    private let authenticator: any Authenticating
    private let settings: ClipSettings

    public init(authenticator: any Authenticating = DeviceAuthenticator(),
                settings: ClipSettings = ClipSettings()) {
        self.authenticator = authenticator
        self.settings = settings
        let enabled = settings.lockEnabled
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    public var canAuthenticate: Bool { authenticator.canAuthenticate() }

    /// Turns the lock on. Requires one successful authentication so the user cannot lock
    /// themselves out with a device that cannot authenticate.
    @discardableResult
    public func enable(reason: String) async -> Bool {
        guard authenticator.canAuthenticate(), !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard await authenticator.authenticate(reason: reason) else { return false }
        settings.lockEnabled = true
        isEnabled = true
        isLocked = false
        return true
    }

    public func disable() {
        settings.lockEnabled = false
        isEnabled = false
        isLocked = false
    }

    public func appDidEnterBackground() {
        if isEnabled { isLocked = true }
    }

    public func unlock(reason: String) async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: reason) { isLocked = false }
    }
}
