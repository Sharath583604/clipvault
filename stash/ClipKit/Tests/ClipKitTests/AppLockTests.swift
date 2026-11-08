import Foundation
import Testing
@testable import ClipKit

struct FakeAuthenticator: Authenticating {
    var available = true
    var succeeds = true
    func canAuthenticate() -> Bool { available }
    func authenticate(reason: String) async -> Bool { succeeds }
}

@MainActor
@Suite struct AppLockTests {
    func settings() -> ClipSettings { ClipSettings(suiteName: "AppLockTests-\(UUID().uuidString)") }

    @Test func disabledByDefaultAndNeverLocks() {
        let lock = AppLock(authenticator: FakeAuthenticator(), settings: settings())
        #expect(!lock.isEnabled && !lock.isLocked)
        lock.appDidEnterBackground()
        #expect(!lock.isLocked)
    }

    @Test func enableRequiresSuccessfulAuthentication() async {
        let failing = AppLock(authenticator: FakeAuthenticator(succeeds: false), settings: settings())
        #expect(await failing.enable(reason: "r") == false)
        #expect(!failing.isEnabled)

        let unavailable = AppLock(authenticator: FakeAuthenticator(available: false), settings: settings())
        #expect(await unavailable.enable(reason: "r") == false)
        #expect(!unavailable.isEnabled)

        let ok = AppLock(authenticator: FakeAuthenticator(), settings: settings())
        #expect(await ok.enable(reason: "r"))
        #expect(ok.isEnabled && !ok.isLocked)
    }

    @Test func locksOnBackgroundAndUnlocksOnlyOnSuccess() async {
        let s = settings()
        let lock = AppLock(authenticator: FakeAuthenticator(), settings: s)
        await lock.enable(reason: "r")
        lock.appDidEnterBackground()
        #expect(lock.isLocked)

        let denied = AppLock(authenticator: FakeAuthenticator(succeeds: false), settings: s)
        #expect(denied.isLocked) // enabled in settings, so it starts locked
        await denied.unlock(reason: "r")
        #expect(denied.isLocked)

        await lock.unlock(reason: "r")
        #expect(!lock.isLocked)
    }

    @Test func settingPersistsAndDisableUnlocks() async {
        let s = settings()
        await AppLock(authenticator: FakeAuthenticator(), settings: s).enable(reason: "r")
        let relaunched = AppLock(authenticator: FakeAuthenticator(), settings: s)
        #expect(relaunched.isEnabled && relaunched.isLocked)
        relaunched.disable()
        #expect(!relaunched.isEnabled && !relaunched.isLocked)
        #expect(!AppLock(authenticator: FakeAuthenticator(), settings: s).isEnabled)
    }
}
