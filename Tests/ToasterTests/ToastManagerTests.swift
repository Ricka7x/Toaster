import XCTest

@testable import Toaster

/// Every test constructs its own `ToastManager` (never `.shared`) backed by a throwaway
/// `UserDefaults` suite cleaned up in `tearDown`, so tests never share state with each
/// other or with a host app's real persisted setting.
@MainActor
final class ToastManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Toaster.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        // `removePersistentDomain` only empties the suite; the (now-empty) file is still
        // left behind, so it has to be deleted explicitly too. Without both, every test
        // run leaves a new file behind in ~/Library/Preferences.
        UserDefaults().removePersistentDomain(forName: suiteName)
        Self.deleteSuitePlist(named: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private static func deleteSuitePlist(named suiteName: String) {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let plistURL = library.appendingPathComponent("Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plistURL)
    }

    // MARK: - isEnabled

    func testIsEnabledDefaultsToTrue() {
        let manager = ToastManager(defaults: defaults)

        XCTAssertTrue(manager.isEnabled)
    }

    func testIsEnabledPersistsAcrossInstancesSharingTheSameSuite() {
        let first = ToastManager(defaults: defaults)
        first.isEnabled = false

        let second = ToastManager(defaults: defaults)

        XCTAssertFalse(second.isEnabled)
    }

    // MARK: - Basic show/dismiss

    func testShowSetsCurrentAndIsPresentedWhenEnabled() {
        let manager = ToastManager(defaults: defaults)

        manager.success("Saved")

        XCTAssertEqual(manager.current?.message, "Saved")
        XCTAssertEqual(manager.current?.style, .success)
        XCTAssertTrue(manager.isPresented)
    }

    func testShowIsANoOpWhenDisabled() {
        let manager = ToastManager(defaults: defaults)
        manager.isEnabled = false

        manager.error("Something went wrong")

        XCTAssertNil(manager.current)
        XCTAssertFalse(manager.isPresented)
    }

    func testShowReplacesAnyPreviousToast() {
        let manager = ToastManager(defaults: defaults)

        manager.info("First")
        manager.success("Second")

        XCTAssertEqual(manager.current?.message, "Second")
        XCTAssertEqual(manager.current?.style, .success)
    }

    func testDismissClearsIsPresentedImmediatelyAndCurrentAfterGracePeriod() {
        let manager = ToastManager(defaults: defaults)
        manager.success("Saved")
        XCTAssertTrue(manager.isPresented)

        manager.dismiss()

        XCTAssertFalse(manager.isPresented)
        XCTAssertNotNil(manager.current, "current stays set through the fade-out grace period")

        let expectation = XCTestExpectation(description: "current clears after the grace period")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNil(manager.current)
    }

    // MARK: - Loading flow

    func testLoadingShowsSpinnerToastAfterDebounce() {
        let manager = ToastManager(defaults: defaults)
        let expectation = XCTestExpectation(description: "loading toast appears")

        manager.loading(message: "Working…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(manager.current?.style, .loading)
        XCTAssertEqual(manager.current?.message, "Working…")
        XCTAssertTrue(manager.isPresented)
    }

    func testCompleteLoadingBeforeDebounceSkipsLoadingPhase() {
        let manager = ToastManager(defaults: defaults)

        manager.loading(message: "Working…")
        manager.completeLoading(message: "Done")

        // Debounce (0.5s) hasn't elapsed yet, so the loading toast never appeared. The
        // result should show immediately instead.
        XCTAssertEqual(manager.current?.style, .success)
        XCTAssertEqual(manager.current?.message, "Done")
    }

    func testCompleteLoadingAfterLoadingAppearedTransitionsToSuccess() {
        let manager = ToastManager(defaults: defaults)
        let appeared = XCTestExpectation(description: "loading toast appears")

        manager.loading(message: "Working…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { appeared.fulfill() }
        wait(for: [appeared], timeout: 1.0)

        manager.completeLoading(message: "Done")

        let transitioned = XCTestExpectation(description: "toast transitions to success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { transitioned.fulfill() }
        wait(for: [transitioned], timeout: 2.0)

        XCTAssertEqual(manager.current?.style, .success)
        XCTAssertEqual(manager.current?.message, "Done")
    }

    func testFailLoadingTransitionsToError() {
        let manager = ToastManager(defaults: defaults)
        let appeared = XCTestExpectation(description: "loading toast appears")

        manager.loading(message: "Working…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { appeared.fulfill() }
        wait(for: [appeared], timeout: 1.0)

        manager.failLoading(message: "Failed")

        let transitioned = XCTestExpectation(description: "toast transitions to error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { transitioned.fulfill() }
        wait(for: [transitioned], timeout: 2.0)

        XCTAssertEqual(manager.current?.style, .error)
        XCTAssertEqual(manager.current?.message, "Failed")
    }

    func testCompleteLoadingIgnoredWhenNoLoadingToastIsCurrent() {
        let manager = ToastManager(defaults: defaults)

        manager.info("Just info")
        manager.completeLoading(message: "Done")

        XCTAssertEqual(manager.current?.style, .info)
        XCTAssertEqual(manager.current?.message, "Just info")
    }

    func testUpdateLoadingChangesMessageOfCurrentLoadingToast() {
        let manager = ToastManager(defaults: defaults)
        let appeared = XCTestExpectation(description: "loading toast appears")

        manager.loading(message: "Step 1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { appeared.fulfill() }
        wait(for: [appeared], timeout: 1.0)

        manager.updateLoading(message: "Step 2")

        XCTAssertEqual(manager.current?.style, .loading)
        XCTAssertEqual(manager.current?.message, "Step 2")
    }

    func testUpdateLoadingIgnoredWhenCurrentToastIsNotLoading() {
        let manager = ToastManager(defaults: defaults)

        manager.success("Done already")
        manager.updateLoading(message: "Should not apply")

        XCTAssertEqual(manager.current?.style, .success)
        XCTAssertEqual(manager.current?.message, "Done already")
    }

    // MARK: - Test-support helpers

    func testCancelAllPendingWorkClearsCurrentAndIsPresented() {
        let manager = ToastManager(defaults: defaults)
        manager.success("Saved")

        manager.cancelAllPendingWork()

        XCTAssertNil(manager.current)
        XCTAssertFalse(manager.isPresented)
    }

    // MARK: - Legacy-settings migration

    func testMigrateLegacyEnabledSettingCopiesValueOnce() {
        defaults.set(false, forKey: "legacy.showToastNotifications")

        ToastManager.migrateLegacyEnabledSetting(fromKey: "legacy.showToastNotifications", defaults: defaults)

        let manager = ToastManager(defaults: defaults)
        XCTAssertFalse(manager.isEnabled)
    }

    func testMigrateLegacyEnabledSettingIsANoOpWhenAlreadyMigrated() {
        defaults.set(true, forKey: "Toaster.isEnabled")
        defaults.set(false, forKey: "legacy.showToastNotifications")

        ToastManager.migrateLegacyEnabledSetting(fromKey: "legacy.showToastNotifications", defaults: defaults)

        let manager = ToastManager(defaults: defaults)
        XCTAssertTrue(manager.isEnabled, "an existing Toaster value should not be overwritten by a legacy one")
    }

    func testMigrateLegacyEnabledSettingIsANoOpWhenNothingWasPersisted() {
        ToastManager.migrateLegacyEnabledSetting(fromKey: "legacy.showToastNotifications", defaults: defaults)

        let manager = ToastManager(defaults: defaults)
        XCTAssertTrue(manager.isEnabled, "falls through to the default when there's no legacy value either")
    }
}
